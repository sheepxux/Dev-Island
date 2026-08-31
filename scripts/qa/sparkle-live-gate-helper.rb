#!/usr/bin/env ruby

require "socket"

MAX_RESPONSE_BYTES = 64 * 1_024 * 1_024
MAX_HEADER_BYTES = 16 * 1_024
MAX_HEADER_LINES = 128

def fail(message, status = 1)
  warn "error: #{message}"
  exit status
end

def open_exclusive(path)
  File.open(
    path,
    File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW,
    0o600
  )
rescue SystemCallError
  fail("private output could not be created")
end

def stable_stat?(before, after)
  %i[dev ino uid mode nlink size mtime ctime].all? do |field|
    before.public_send(field) == after.public_send(field)
  end
end

def read_bounded_file(path, root)
  expanded = File.expand_path(path)
  fail("served path escaped its private root") unless
    expanded.start_with?("#{root}/")

  File.open(expanded, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
    before = file.stat
    fail("served object is not a regular file") unless before.file?
    fail("served object has an unsafe owner") unless before.uid == Process.uid
    fail("served object has an unsafe link count") unless before.nlink == 1
    fail("served object has unsafe permissions") unless (before.mode & 0o022).zero?
    fail("served object exceeds the live-gate limit") unless
      before.size.between?(1, MAX_RESPONSE_BYTES)

    data = file.read(MAX_RESPONSE_BYTES + 1)
    after = file.stat
    fail("served object changed while being read") unless stable_stat?(before, after)
    fail("served object read was incomplete") unless data.bytesize == before.size
    data
  end
rescue Errno::ENOENT, Errno::ELOOP
  nil
rescue SystemCallError
  fail("served object could not be opened safely")
end

def wait_for_line(client, timeout: 2.0)
  ready = IO.select([client], nil, nil, timeout)
  return nil if ready.nil?

  client.gets
end

def run_server(arguments)
  fail("Usage: sparkle-live-gate-helper.rb serve ROOT PORT_FILE LOG_FILE", 64) unless
    arguments.length == 3

  root_argument, port_path, log_path = arguments
  root = File.realpath(root_argument)
  root_stat = File.stat(root)
  fail("server root is not a private directory") unless
    root_stat.directory? &&
      root_stat.uid == Process.uid &&
      (root_stat.mode & 0o077).zero?

  port_file = open_exclusive(port_path)
  request_log = open_exclusive(log_path)
  server = TCPServer.new("127.0.0.1", 0)
  server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

  port_file.write("#{server.local_address.ip_port}\n")
  port_file.flush
  port_file.fsync
  port_file.close

  stop_requested = false
  stop = proc do
    stop_requested = true
  end
  Signal.trap("INT", &stop)
  Signal.trap("TERM", &stop)

  until stop_requested
    ready = IO.select([server], nil, nil, 0.1)
    next if ready.nil?

    begin
      client = server.accept_nonblock
    rescue IO::WaitReadable
      next
    rescue IOError, Errno::EBADF, Errno::EINVAL
      break if stop_requested
      raise
    end

    begin
      request_line = wait_for_line(client)
      next if request_line.nil? || request_line.bytesize > 2_048

      header_bytes = request_line.bytesize
      header_lines = 0
      loop do
        line = wait_for_line(client)
        break if line.nil? || line == "\r\n" || line == "\n"

        header_bytes += line.bytesize
        header_lines += 1
        break if header_bytes > MAX_HEADER_BYTES || header_lines > MAX_HEADER_LINES
      end
      next if header_bytes > MAX_HEADER_BYTES || header_lines > MAX_HEADER_LINES

      match = request_line.match(%r{\A(GET|HEAD) (/([A-Za-z0-9.-]+)) HTTP/1\.[01]\r?\n\z})
      unless match
        client.write("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
        next
      end

      method = match[1]
      target = match[2]
      name = match[3]
      unless name.match?(/\A(?:feed-[a-z-]+\.xml|update-[a-z-]+\.zip)\z/)
        client.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
        next
      end

      data = read_bounded_file(File.join(root, name), root)
      if data.nil?
        client.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
        next
      end

      request_log.write("#{method} #{target}\n")
      request_log.flush
      content_type = name.end_with?(".xml") ? "application/xml" : "application/octet-stream"
      client.write(
        "HTTP/1.1 200 OK\r\n" \
        "Connection: close\r\n" \
        "Content-Type: #{content_type}\r\n" \
        "Content-Length: #{data.bytesize}\r\n\r\n"
      )
      client.write(data) if method == "GET"
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError
      nil
    ensure
      client.close rescue nil
    end
  end
ensure
  request_log&.close
  server&.close rescue nil
end

def process_group_exists?(process_group)
  return false unless process_group.is_a?(Integer) && process_group.positive?

  Process.kill(0, -process_group)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

def terminate_process_group(process_group)
  return unless process_group && process_group.positive?
  return unless process_group_exists?(process_group)

  Process.kill("TERM", -process_group) rescue nil
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0
  while process_group_exists?(process_group) &&
      Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    sleep 0.02
  end
  Process.kill("KILL", -process_group) rescue nil if process_group_exists?(process_group)
end

def run_bounded(arguments)
  separator = arguments.index("--")
  fail("Usage: sparkle-live-gate-helper.rb run SECONDS STDOUT STDERR -- COMMAND...", 64) unless
    separator == 3 && arguments.length >= 5

  timeout = Float(arguments[0], exception: false)
  fail("bounded duration is invalid", 64) unless timeout&.between?(1.0, 300.0)
  stdout_path = arguments[1]
  stderr_path = arguments[2]
  command = arguments[(separator + 1)..]

  stdout = open_exclusive(stdout_path)
  stderr = open_exclusive(stderr_path)
  process_group = nil
  child_status = nil
  timed_out = false

  begin
    process_group = Process.spawn(*command, pgroup: true, out: stdout, err: stderr, close_others: true)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      waited_pid, status = Process.waitpid2(process_group, Process::WNOHANG)
      if waited_pid
        child_status = status
        break
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        timed_out = true
        break
      end
      sleep 0.02
    end
  ensure
    terminate_process_group(process_group) if timed_out || process_group_exists?(process_group)
    begin
      Process.waitpid(process_group) if process_group && child_status.nil?
    rescue Errno::ECHILD
      nil
    end
    stdout.close
    stderr.close
  end

  exit 124 if timed_out
  exit(child_status.exitstatus) if child_status.exited?
  exit(128 + child_status.termsig) if child_status.signaled?
  exit 1
end

command = ARGV.shift
case command
when "serve"
  run_server(ARGV)
when "run"
  run_bounded(ARGV)
else
  fail("Usage: sparkle-live-gate-helper.rb serve|run ...", 64)
end
