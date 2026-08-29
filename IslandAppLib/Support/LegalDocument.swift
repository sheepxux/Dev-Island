import AppKit
import Darwin
import Foundation
import SwiftUI

enum LegalDocumentKind: String, CaseIterable, Identifiable, Sendable {
    case privacy
    case terms

    var id: String { rawValue }

    var resourceName: String {
        switch self {
        case .privacy: return "PRIVACY"
        case .terms: return "TERMS"
        }
    }

    func buttonTitle(language: DevIslandLanguage) -> String {
        switch self {
        case .privacy:
            return L10n.string("Privacy Notice", language: language)
        case .terms:
            return L10n.string("Terms of Use", language: language)
        }
    }

    func expectedDocumentTitle(language: DevIslandLanguage) -> String {
        let isChinese = language.resolvedIdentifier == "zh-Hans"
        switch (self, isChinese) {
        case (.privacy, false): return "Dev Island Privacy Notice"
        case (.privacy, true): return "Dev Island 隐私说明"
        case (.terms, false): return "Dev Island Terms of Use"
        case (.terms, true): return "Dev Island 使用条款"
        }
    }
}

enum LegalDocumentBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case callout(String)
}

struct LegalDocumentPresentation: Equatable, Sendable {
    let kind: LegalDocumentKind
    let title: String
    let lastUpdated: String
    let blocks: [LegalDocumentBlock]
}

enum LegalDocumentError: Error, Equatable {
    case missingResource
    case unsafeResource
    case invalidEncoding
    case invalidStructure
}

enum LegalDocumentParser {
    static let maximumDocumentBytes = 512 * 1024
    private static let bilingualSeparator = "\n---\n\n"

    static func decode(
        _ data: Data,
        kind: LegalDocumentKind,
        language: DevIslandLanguage
    ) throws -> LegalDocumentPresentation {
        guard !data.isEmpty, data.count <= maximumDocumentBytes else {
            throw LegalDocumentError.unsafeResource
        }
        guard let completeText = String(data: data, encoding: .utf8) else {
            throw LegalDocumentError.invalidEncoding
        }

        let sections = completeText.components(separatedBy: bilingualSeparator)
        guard sections.count == 2 else {
            throw LegalDocumentError.invalidStructure
        }
        // Validate both reviewed halves even when only one language is shown. A
        // damaged or unexpectedly edited companion section must fail closed as
        // one bundled legal document, rather than remaining hidden until the
        // user changes languages.
        let english = try parseSection(
            sections[0],
            kind: kind,
            language: .english
        )
        let chinese = try parseSection(
            sections[1],
            kind: kind,
            language: .simplifiedChinese
        )
        return language.resolvedIdentifier == "zh-Hans" ? chinese : english
    }

    private static func parseSection(
        _ section: String,
        kind: LegalDocumentKind,
        language: DevIslandLanguage
    ) throws -> LegalDocumentPresentation {
        let lines = section.components(separatedBy: .newlines)
        guard let titleLine = lines.first,
              titleLine.hasPrefix("# ") else {
            throw LegalDocumentError.invalidStructure
        }
        let title = String(titleLine.dropFirst(2))
        guard title == kind.expectedDocumentTitle(language: language) else {
            throw LegalDocumentError.invalidStructure
        }

        let datePrefix = language.resolvedIdentifier == "zh-Hans"
            ? "最后更新："
            : "Last updated:"
        guard let lastUpdated = lines.first(where: { $0.hasPrefix(datePrefix) }),
              !lastUpdated.dropFirst(datePrefix.count).trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LegalDocumentError.invalidStructure
        }

        let contentLines = Array(lines.dropFirst()).filter { $0 != lastUpdated }
        let blocks = parseBlocks(contentLines)
        guard !blocks.isEmpty,
              blocks.contains(where: {
                  if case .callout = $0 { return true }
                  return false
              }) else {
            throw LegalDocumentError.invalidStructure
        }

        return LegalDocumentPresentation(
            kind: kind,
            title: title,
            lastUpdated: lastUpdated,
            blocks: blocks
        )
    }

    private enum PendingBlock {
        case paragraph([String])
        case bullet([String])
        case callout([String])
    }

    private static func parseBlocks(_ lines: [String]) -> [LegalDocumentBlock] {
        var result: [LegalDocumentBlock] = []
        var pending: PendingBlock?

        func joined(_ parts: [String]) -> String {
            parts.reduce(into: "") { accumulated, rawPart in
                let part = rawPart.trimmingCharacters(in: .whitespaces)
                guard !part.isEmpty else { return }
                if !accumulated.isEmpty,
                   shouldInsertSpace(after: accumulated, before: part) {
                    accumulated.append(" ")
                }
                accumulated.append(part)
            }
        }

        func flush() {
            guard let current = pending else { return }
            pending = nil
            switch current {
            case .paragraph(let lines):
                let text = joined(lines)
                if !text.isEmpty { result.append(.paragraph(text)) }
            case .bullet(let lines):
                let text = joined(lines)
                if !text.isEmpty { result.append(.bullet(text)) }
            case .callout(let lines):
                let text = joined(lines)
                if !text.isEmpty { result.append(.callout(text)) }
            }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }

            let headingLevel = line.prefix { $0 == "#" }.count
            if (2...4).contains(headingLevel),
               line.dropFirst(headingLevel).hasPrefix(" ") {
                flush()
                result.append(.heading(
                    level: headingLevel,
                    text: String(line.dropFirst(headingLevel + 1))
                ))
                continue
            }

            if line.hasPrefix("> ") {
                let content = String(line.dropFirst(2))
                switch pending {
                case .callout(var parts):
                    parts.append(content)
                    pending = .callout(parts)
                default:
                    flush()
                    pending = .callout([content])
                }
                continue
            }

            if line.hasPrefix("- ") {
                flush()
                pending = .bullet([String(line.dropFirst(2))])
                continue
            }

            switch pending {
            case .paragraph(var parts):
                parts.append(line)
                pending = .paragraph(parts)
            case .bullet(var parts):
                parts.append(line)
                pending = .bullet(parts)
            case .callout(var parts):
                parts.append(line)
                pending = .callout(parts)
            case nil:
                pending = .paragraph([line])
            }
        }
        flush()
        return result
    }

    private static func shouldInsertSpace(after left: String, before right: String) -> Bool {
        guard let leftScalar = left.unicodeScalars.last,
              let rightScalar = right.unicodeScalars.first else {
            return false
        }
        return !isCJK(leftScalar) && !isCJK(rightScalar)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }
}

enum DescriptorBackedResourceReader {
    static let minimumDocumentBytes = 1 * 1024

    private struct FileSnapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let linkCount: nlink_t
        let size: off_t
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let statusChangeSeconds: Int64
        let statusChangeNanoseconds: Int64

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            mode = status.st_mode
            linkCount = status.st_nlink
            size = status.st_size
            modificationSeconds = Int64(status.st_mtimespec.tv_sec)
            modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
            statusChangeSeconds = Int64(status.st_ctimespec.tv_sec)
            statusChangeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
        }
    }

    static func read(
        at url: URL,
        afterInitialValidation: (() -> Void)? = nil
    ) throws -> Data {
        let maximumBytes = LegalDocumentParser.maximumDocumentBytes

        let descriptor = try openReadOnlyDescriptor(at: url)
        defer { Darwin.close(descriptor) }

        let initial = try descriptorSnapshot(descriptor)
        try validate(initial, maximumBytes: maximumBytes)
        afterInitialValidation?()

        var data = Data()
        data.reserveCapacity(Int(initial.size))
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumBytes + 1))

        while true {
            let remainingWithOverflowSentinel = maximumBytes - data.count + 1
            guard remainingWithOverflowSentinel > 0 else {
                throw LegalDocumentError.unsafeResource
            }
            let requestedBytes = min(buffer.count, remainingWithOverflowSentinel)
            let bytesRead: Int = try buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    throw LegalDocumentError.unsafeResource
                }
                var result: Int
                repeat {
                    result = Darwin.read(descriptor, baseAddress, requestedBytes)
                } while result < 0 && errno == EINTR
                guard result >= 0 else {
                    throw LegalDocumentError.unsafeResource
                }
                return result
            }
            guard bytesRead > 0 else { break }
            data.append(contentsOf: buffer.prefix(bytesRead))
            guard data.count <= maximumBytes else {
                throw LegalDocumentError.unsafeResource
            }
        }

        let finalDescriptor = try descriptorSnapshot(descriptor)
        let finalPath = try pathSnapshot(url)
        guard initial == finalDescriptor,
              initial == finalPath,
              data.count == Int(initial.size) else {
            throw LegalDocumentError.unsafeResource
        }
        return data
    }

    private static func openReadOnlyDescriptor(at url: URL) throws -> Int32 {
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, flags)
        }
        guard descriptor >= 0 else {
            throw LegalDocumentError.unsafeResource
        }
        return descriptor
    }

    private static func descriptorSnapshot(_ descriptor: Int32) throws -> FileSnapshot {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw LegalDocumentError.unsafeResource
        }
        return FileSnapshot(status)
    }

    private static func pathSnapshot(_ url: URL) throws -> FileSnapshot {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &status)
        }
        guard result == 0 else {
            throw LegalDocumentError.unsafeResource
        }
        return FileSnapshot(status)
    }

    private static func validate(
        _ snapshot: FileSnapshot,
        maximumBytes: Int
    ) throws {
        let unsafeWriteBits = mode_t(S_IWGRP | S_IWOTH)
        let unsafeSpecialBits = mode_t(S_ISUID | S_ISGID)
        guard (snapshot.mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              snapshot.linkCount == 1,
              snapshot.size >= off_t(minimumDocumentBytes),
              snapshot.size <= off_t(maximumBytes),
              (snapshot.mode & unsafeWriteBits) == 0,
              (snapshot.mode & unsafeSpecialBits) == 0 else {
            throw LegalDocumentError.unsafeResource
        }
    }
}

enum BundledLegalDocumentLoader {
    static func load(
        kind: LegalDocumentKind,
        language: DevIslandLanguage,
        bundle: Bundle = .main
    ) throws -> LegalDocumentPresentation {
        guard let url = bundle.url(
            forResource: kind.resourceName,
            withExtension: "md",
            subdirectory: "Legal"
        ) else {
            throw LegalDocumentError.missingResource
        }

        let data = try DescriptorBackedResourceReader.read(at: url)
        return try LegalDocumentParser.decode(data, kind: kind, language: language)
    }
}

enum LegalDocumentLinkPolicy {
    private static let allowedSupportAddresses: Set<String> = [
        "alsoaxu@gmail.com",
        "puzhen913@gmail.com",
    ]

    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "mailto":
            guard url.query == nil, url.fragment == nil else { return false }
            return allowedSupportAddresses.contains(
                url.path.removingPercentEncoding?.lowercased() ?? ""
            )
        case "https":
            return url.host?.lowercased() == "devisland.app"
                && url.user == nil
                && url.password == nil
                && url.port == nil
        default:
            return false
        }
    }

    static func attributedText(_ source: String) -> AttributedString {
        let pattern = #"\[([^\]\n]+)\]\(([^)\s]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return inlineMarkdown(source)
        }

        let sourceNSString = source as NSString
        let fullRange = NSRange(location: 0, length: sourceNSString.length)
        let matches = expression.matches(in: source, range: fullRange)
        guard !matches.isEmpty else {
            return removingUnsafeLinks(from: inlineMarkdown(source))
        }

        var result = AttributedString()
        var cursor = 0
        for match in matches {
            guard match.range.location >= cursor else { continue }

            if match.range.location > cursor {
                let prefixRange = NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )
                result.append(removingUnsafeLinks(
                    from: inlineMarkdown(sourceNSString.substring(with: prefixRange))
                ))
            }

            var label = inlineMarkdown(sourceNSString.substring(with: match.range(at: 1)))
            let destination = sourceNSString.substring(with: match.range(at: 2))
            if let url = URL(string: destination), allows(url), !label.characters.isEmpty {
                label[label.startIndex..<label.endIndex].link = url
            } else {
                label = removingUnsafeLinks(from: label)
            }
            result.append(label)
            cursor = NSMaxRange(match.range)
        }

        if cursor < fullRange.length {
            let suffixRange = NSRange(location: cursor, length: fullRange.length - cursor)
            result.append(removingUnsafeLinks(
                from: inlineMarkdown(sourceNSString.substring(with: suffixRange))
            ))
        }
        return result
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

    private static func removingUnsafeLinks(
        from source: AttributedString
    ) -> AttributedString {
        var sanitized = source
        let unsafeRanges = sanitized.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link, !allows(link) else { return nil }
            return run.range
        }
        for range in unsafeRanges {
            sanitized[range].link = nil
        }
        return sanitized
    }
}

struct LegalDocumentSheet: View {
    let kind: LegalDocumentKind
    private let previewPresentation: LegalDocumentPresentation?
    private let previewAppVersion: String?
    @State private var presentation: LegalDocumentPresentation?
    @State private var loadFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devIslandLanguage) private var language

    init(
        kind: LegalDocumentKind,
        previewPresentation: LegalDocumentPresentation? = nil,
        previewAppVersion: String? = nil
    ) {
        self.kind = kind
        self.previewPresentation = previewPresentation
        self.previewAppVersion = previewAppVersion
        _presentation = State(initialValue: previewPresentation)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            if let presentation {
                documentBody(presentation)
            } else if loadFailed {
                failureBody
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(
                        L10n.string("Loading legal document", language: language)
                    )
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            footer
        }
        .frame(width: 640, height: 540)
        .background(Palette.tourCanvas)
        .foregroundStyle(Palette.warmWhite)
        .preferredColorScheme(.dark)
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: language) { _, _ in loadIfNeeded(force: true) }
        .environment(\.openURL, OpenURLAction { url in
            guard LegalDocumentLinkPolicy.allows(url) else { return .discarded }
            return NSWorkspace.shared.open(url) ? .handled : .discarded
        })
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("LEGAL · LOCAL COPY", language: language))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(Palette.textTertiary)

                Text(presentation?.title ?? kind.buttonTitle(language: language))
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(Palette.warmWhite)
            }

            Spacer(minLength: 16)

            Button(L10n.string("Done", language: language)) {
                dismiss()
            }
            .buttonStyle(SettingsControlButtonStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityHint(
                L10n.string("Closes the legal document", language: language)
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
    }

    private func documentBody(_ presentation: LegalDocumentPresentation) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(presentation.lastUpdated)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel(presentation.lastUpdated)

                ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: LegalDocumentBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(LegalDocumentLinkPolicy.attributedText(text))
                .font(.system(
                    size: level == 2 ? 15.5 : 13.5,
                    weight: level == 2 ? .semibold : .medium
                ))
                .tracking(level == 2 ? -0.15 : 0)
                .foregroundStyle(Palette.warmWhite)
                .padding(.top, level == 2 ? 8 : 2)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(LegalDocumentLinkPolicy.attributedText(text))
                .font(.system(size: 12.25))
                .lineSpacing(4)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("—")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
                Text(LegalDocumentLinkPolicy.attributedText(text))
                    .font(.system(size: 12.25))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .callout(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Palette.textTertiary)
                    .frame(width: 1.5)
                    .accessibilityHidden(true)
                Text(LegalDocumentLinkPolicy.attributedText(text))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
        }
    }

    private var failureBody: some View {
        VStack(spacing: 10) {
            Text(L10n.string("Legal document unavailable", language: language))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.string(
                "The bundled copy could not be verified. Reinstall a signed Dev Island build before relying on it.",
                language: language
            ))
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(L10n.string("Bundled with this app version", language: language))
            Text("·")
                .accessibilityHidden(true)
            Text(appVersion)
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .foregroundStyle(Palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .frame(height: 42)
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        previewAppVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.3.0"
    }

    private func loadIfNeeded(force: Bool = false) {
        if previewPresentation != nil { return }
        if presentation != nil, !force { return }
        do {
            presentation = try BundledLegalDocumentLoader.load(
                kind: kind,
                language: language
            )
            loadFailed = false
        } catch {
            presentation = nil
            loadFailed = true
        }
    }
}
