import Foundation

// Adds an import to a derived executable. The original executable is never written.
// The imported DLL redirects only the movie routine in memory after checking its prologue.
public enum MoviePatch
{
    public static func executable(original: URL, game: Game, destination: URL) throws
    {
        guard try Files.sha256(original) == GameSource.legacyHashes[game.rawValue] else
        {
            throw CentauriError.message("Native movies currently support the verified legacy GOG executables only.")
        }
        let patched = try addImport(to: Data(contentsOf: original))
        if Files.isLink(destination) { try FileManager.default.removeItem(at: destination) }
        try patched.write(to: destination, options: .atomic)
    }

    public static func addImport(to original: Data) throws -> Data
    {
        var image = original
        func invalid() -> CentauriError { .message("Unsupported or malformed Windows executable layout.") }
        func word(_ offset: Int) throws -> Int
        {
            guard offset >= 0, offset <= image.count - 2 else { throw invalid() }
            return Int(image[offset]) | Int(image[offset + 1]) << 8
        }
        func dword(_ offset: Int) throws -> Int
        {
            guard offset >= 0, offset <= image.count - 4 else { throw invalid() }
            return Int(image[offset]) | Int(image[offset + 1]) << 8 | Int(image[offset + 2]) << 16 | Int(image[offset + 3]) << 24
        }
        func put(_ offset: Int, _ value: Int, count: Int = 4)
        {
            for i in 0..<count { image[offset + i] = UInt8((value >> (i * 8)) & 255) }
        }
        func align(_ value: Int, _ alignment: Int) -> Int { (value + alignment - 1) & ~(alignment - 1) }
        guard image.count >= 256, image.count < 128_000_000, try word(0) == 0x5a4d else { throw invalid() }
        let pe = try dword(60)
        guard try dword(pe) == 0x4550, try word(pe + 4) == 0x14c else { throw invalid() }
        let count = try word(pe + 6)
        let optionalSize = try word(pe + 20)
        let optional = pe + 24
        guard count > 0, count < 64, optionalSize >= 224,
              try word(optional) == 0x10b, try dword(optional + 28) == 0x400000 else { throw invalid() }
        let table = optional + optionalSize
        let sectionAlignment = try dword(optional + 32)
        let fileAlignment = try dword(optional + 36)
        guard fileAlignment >= 512, fileAlignment <= 65536, fileAlignment.nonzeroBitCount == 1,
              sectionAlignment >= fileAlignment, sectionAlignment <= 1_048_576,
              sectionAlignment.nonzeroBitCount == 1 else { throw invalid() }
        var sections: [(rva: Int, virtualSize: Int, raw: Int, rawSize: Int)] = []
        for index in 0..<count
        {
            let header = table + 40 * index
            let section = (rva: try dword(header + 12), virtualSize: try dword(header + 8),
                           raw: try dword(header + 20), rawSize: try dword(header + 16))
            guard section.raw <= image.count, section.rawSize <= image.count - section.raw else { throw invalid() }
            sections.append(section)
        }
        let newHeader = table + count * 40
        let firstRaw = sections.filter { $0.raw > 0 }.map(\.raw).min() ?? 0
        guard newHeader + 40 <= firstRaw, newHeader + 40 <= (try dword(optional + 60)) else { throw invalid() }
        func offset(_ rva: Int) throws -> Int
        {
            for section in sections where rva >= section.rva && rva - section.rva < section.rawSize
            {
                return section.raw + rva - section.rva
            }
            throw invalid()
        }
        var importOffset = try offset(dword(optional + 104))
        var descriptors = Data()
        var terminated = false
        for _ in 0..<128
        {
            guard importOffset >= 0, importOffset <= image.count - 20 else { throw invalid() }
            let entry = image[importOffset..<importOffset + 20]
            if entry.allSatisfy({ $0 == 0 }) { terminated = true; break }
            descriptors.append(entry)
            importOffset += 20
        }
        guard terminated else { throw invalid() }
        let lastVirtual = sections.map { $0.rva + max($0.virtualSize, $0.rawSize) }.max()!
        guard lastVirtual < 0x40000000 else { throw invalid() }
        let rva = align(lastVirtual, sectionAlignment)
        let raw = align(image.count, fileAlignment)
        var payload = descriptors
        let newDescriptor = payload.count
        payload.append(Data(repeating: 0, count: 40)) // new descriptor and zero terminator
        let dllName = payload.count
        payload.append(Data("centauri_movies.dll\0".utf8))
        if payload.count % 2 != 0 { payload.append(0) }
        let importName = payload.count
        payload.append(contentsOf: [0, 0])
        payload.append(Data("Initialize\0".utf8))
        while payload.count % 4 != 0 { payload.append(0) }
        let lookup = payload.count
        payload.append(Data(repeating: 0, count: 16)) // lookup table and IAT
        func payloadDword(_ offset: Int, _ value: Int)
        {
            for i in 0..<4 { payload[offset + i] = UInt8((value >> (i * 8)) & 255) }
        }
        payloadDword(newDescriptor, rva + lookup)
        payloadDword(newDescriptor + 12, rva + dllName)
        payloadDword(newDescriptor + 16, rva + lookup + 8)
        payloadDword(lookup, rva + importName)
        payloadDword(lookup + 8, rva + importName)
        let virtualSize = payload.count
        let rawSize = align(virtualSize, fileAlignment)
        image.append(Data(repeating: 0, count: raw - image.count))
        image.append(payload)
        image.append(Data(repeating: 0, count: rawSize - virtualSize))
        for i in 0..<40 { image[newHeader + i] = 0 }
        image.replaceSubrange(newHeader..<newHeader + 8, with: Data(".ctmovie".utf8))
        put(newHeader + 8, virtualSize)
        put(newHeader + 12, rva)
        put(newHeader + 16, rawSize)
        put(newHeader + 20, raw)
        put(newHeader + 36, 0xc0000040) // initialized, readable, writable data
        put(pe + 6, count + 1, count: 2)
        let initializedSize = try dword(optional + 8) + rawSize
        guard initializedSize <= 0xffffffff else { throw invalid() }
        put(optional + 8, initializedSize)
        put(optional + 56, align(rva + virtualSize, sectionAlignment))
        put(optional + 64, 0) // checksum must not claim to match the original image
        put(optional + 104, rva)
        put(optional + 108, descriptors.count + 40)
        put(optional + 128, 0) // remove the derived image's obsolete Authenticode directory
        put(optional + 132, 0)
        put(optional + 184, 0) // bound imports no longer apply
        put(optional + 188, 0)
        return image
    }
}
