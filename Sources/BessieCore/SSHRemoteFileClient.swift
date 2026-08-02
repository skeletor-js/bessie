import Foundation

/// Multiplexed OpenSSH access to a remote host, reusing Bessie's ControlMaster tunnel.
public struct SSHRemoteFileAccess: Equatable, Sendable, Hashable {
    public let host: String
    public let controlPath: String
    public let sshExecutablePath: String

    public init(host: String, controlPath: String, sshExecutablePath: String = "/usr/bin/ssh") {
        self.host = host
        self.controlPath = controlPath
        self.sshExecutablePath = sshExecutablePath
    }
}

public struct SSHRemoteFileClient: Sendable {
    public let access: SSHRemoteFileAccess
    private let timeout: TimeInterval

    public init(access: SSHRemoteFileAccess, timeout: TimeInterval = 20) {
        self.access = access
        self.timeout = timeout
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
    }

    public struct Stat: Equatable, Sendable {
        public let exists: Bool
        public let isDirectory: Bool
        public let isSymbolicLink: Bool
        public let isRegularFile: Bool
        public let byteSize: Int
        public let modificationDate: Date?
    }

    public func listDirectory(_ absolutePath: String, limit: Int) throws -> [Entry] {
        let payload = try request([
            "op": "list",
            "path": absolutePath,
            "limit": limit,
        ])
        guard let items = payload["items"] as? [[String: Any]] else { throw WorkspacePathError.unreadable }
        return items.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return Entry(
                name: name,
                isDirectory: item["is_dir"] as? Bool ?? false,
                isSymbolicLink: item["is_link"] as? Bool ?? false
            )
        }
    }

    public func stat(_ absolutePath: String) throws -> Stat {
        let payload = try request([
            "op": "stat",
            "path": absolutePath,
        ])
        return Stat(
            exists: payload["exists"] as? Bool ?? false,
            isDirectory: payload["is_dir"] as? Bool ?? false,
            isSymbolicLink: payload["is_link"] as? Bool ?? false,
            isRegularFile: payload["is_file"] as? Bool ?? false,
            byteSize: payload["size"] as? Int ?? 0,
            modificationDate: (payload["mtime"] as? Double).map { Date(timeIntervalSince1970: $0) }
        )
    }

    public func readFile(_ absolutePath: String, maximumByteSize: Int) throws -> Data {
        let payload = try request([
            "op": "read",
            "path": absolutePath,
            "max_bytes": maximumByteSize,
        ])
        if payload["too_large"] as? Bool == true { throw WorkspacePathError.tooLarge }
        guard let b64 = payload["data_b64"] as? String,
              let data = Data(base64Encoded: b64) else { throw WorkspacePathError.unreadable }
        return data
    }

    public func writeFile(_ absolutePath: String, data: Data) throws {
        _ = try request([
            "op": "write",
            "path": absolutePath,
            "data_b64": data.base64EncodedString(),
        ])
    }

    public func move(from source: String, to destination: String) throws {
        _ = try request([
            "op": "move",
            "from": source,
            "to": destination,
        ])
    }

    public func delete(_ absolutePath: String) throws {
        _ = try request([
            "op": "delete",
            "path": absolutePath,
        ])
    }

    public func findGitTopLevel(from absolutePath: String) throws -> String? {
        let payload = try request([
            "op": "git_toplevel",
            "path": absolutePath,
        ])
        return payload["path"] as? String
    }

    public func snapshotSignatures(root absolutePath: String, ignoreNames: [String]) throws -> [String: (mtime: Double?, size: Int?)] {
        let payload = try request([
            "op": "snapshot",
            "path": absolutePath,
            "ignore": ignoreNames,
        ])
        guard let files = payload["files"] as? [String: [String: Any]] else { return [:] }
        var result: [String: (mtime: Double?, size: Int?)] = [:]
        for (path, meta) in files {
            result[path] = (meta["mtime"] as? Double, meta["size"] as? Int)
        }
        return result
    }

    public func runGit(arguments: [String], maximumBytes: Int = 1_500_000) throws -> (status: Int32, data: Data) {
        let payload = try request([
            "op": "git",
            "args": arguments,
            "max_bytes": maximumBytes,
        ])
        let status = payload["status"] as? Int ?? 1
        let b64 = payload["data_b64"] as? String ?? ""
        let data = Data(base64Encoded: b64) ?? Data()
        return (Int32(status), data)
    }

    public func downloadToTemporaryFile(_ absolutePath: String, maximumByteSize: Int = 40 * 1_024 * 1_024) throws -> URL {
        let data = try readFile(absolutePath, maximumByteSize: maximumByteSize)
        let ext = URL(fileURLWithPath: absolutePath).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-remote-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func request(_ object: [String: Any]) throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: object, options: [])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: access.sshExecutablePath)
        process.arguments = [
            "-S", access.controlPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            access.host,
            "python3", "-c", Self.remotePython,
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() }
        catch { throw BessieConnectionError.sshFailed(error.localizedDescription) }
        stdin.fileHandleForWriting.write(body)
        try? stdin.fileHandleForWriting.close()

        let deadline = Date(timeIntervalSinceNow: timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw BessieConnectionError.sshFailed("Timed out waiting for remote file operation.")
        }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let reason = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BessieConnectionError.sshFailed(reason?.isEmpty == false ? reason! : "Remote file command failed (\(process.terminationStatus)).")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        else { throw WorkspacePathError.unreadable }
        if let error = json["error"] as? String {
            switch error {
            case "not_found": throw WorkspacePathError.notFound
            case "not_directory": throw WorkspacePathError.notDirectory
            case "unreadable": throw WorkspacePathError.unreadable
            case "path_escape": throw WorkspacePathError.pathEscape
            case "too_large": throw WorkspacePathError.tooLarge
            case "destination_exists": throw WorkspaceFileOperationError.destinationExists
            case "symlink": throw WorkspaceFileOperationError.symbolicLinkUnsupported
            default: throw WorkspacePathError.unreadable
            }
        }
        return json
    }

    /// Compact remote helper. Runs on the remote host under the multiplexed SSH session.
    private static let remotePython = #"""
import base64, json, os, shutil, stat, subprocess, sys, time
req=json.load(sys.stdin)
op=req.get("op")
def ok(**kw):
    print(json.dumps(kw)); sys.exit(0)
def err(code):
    print(json.dumps({"error": code})); sys.exit(0)
def is_abs(p): return isinstance(p,str) and p.startswith("/")
path=req.get("path")
if op=="list":
    if not is_abs(path): err("path_escape")
    if not os.path.isdir(path): err("not_directory")
    limit=int(req.get("limit") or 2000)
    items=[]
    try: names=sorted(os.listdir(path))
    except Exception: err("unreadable")
    for name in names:
        if name.startswith('.'): continue
        full=os.path.join(path,name)
        try:
            st=os.lstat(full)
            is_link=stat.S_ISLNK(st.st_mode)
            is_dir=stat.S_ISDIR(st.st_mode) and not is_link
        except Exception:
            continue
        items.append({"name":name,"is_dir":bool(is_dir),"is_link":bool(is_link)})
        if len(items)>=limit: break
    ok(items=items)
elif op=="stat":
    if not is_abs(path): err("path_escape")
    if not os.path.lexists(path): ok(exists=False,is_dir=False,is_link=False,is_file=False,size=0,mtime=None)
    st=os.lstat(path)
    ok(exists=True,is_dir=stat.S_ISDIR(st.st_mode) and not stat.S_ISLNK(st.st_mode),is_link=stat.S_ISLNK(st.st_mode),is_file=stat.S_ISREG(st.st_mode),size=int(st.st_size),mtime=float(st.st_mtime))
elif op=="read":
    if not is_abs(path): err("path_escape")
    maxb=int(req.get("max_bytes") or 2097152)
    if not os.path.isfile(path): err("not_found")
    size=os.path.getsize(path)
    if size>maxb: ok(too_large=True)
    with open(path,"rb") as f: data=f.read()
    ok(data_b64=base64.b64encode(data).decode("ascii"), size=size)
elif op=="write":
    if not is_abs(path): err("path_escape")
    raw=base64.b64decode(req.get("data_b64") or "")
    parent=os.path.dirname(path)
    if not os.path.isdir(parent): err("not_found")
    tmp=path+".bessie-tmp-"+str(os.getpid())
    with open(tmp,"wb") as f: f.write(raw)
    os.replace(tmp,path)
    ok(ok=True)
elif op=="move":
    src=req.get("from"); dst=req.get("to")
    if not is_abs(src) or not is_abs(dst): err("path_escape")
    if os.path.lexists(dst): err("destination_exists")
    if os.path.islink(src): err("symlink")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.move(src,dst)
    ok(ok=True)
elif op=="delete":
    if not is_abs(path): err("path_escape")
    if os.path.islink(path): err("symlink")
    if not os.path.lexists(path): err("not_found")
    if os.path.isdir(path) and not os.path.islink(path): shutil.rmtree(path)
    else: os.remove(path)
    ok(ok=True)
elif op=="git_toplevel":
    if not is_abs(path): err("path_escape")
    cur=path
    while True:
        if os.path.exists(os.path.join(cur,".git")): ok(path=cur)
        parent=os.path.dirname(cur)
        if parent==cur: ok(path=None)
        cur=parent
elif op=="snapshot":
    if not is_abs(path): err("path_escape")
    ignore=set(req.get("ignore") or [])
    files={}
    for root, dirs, names in os.walk(path):
        dirs[:] = [d for d in dirs if d not in ignore and not d.startswith('.')]
        rel_root=os.path.relpath(root, path)
        if rel_root==".": rel_root=""
        for name in names:
            if name.startswith('.'): continue
            full=os.path.join(root,name)
            try:
                st=os.lstat(full)
                if not stat.S_ISREG(st.st_mode): continue
            except Exception:
                continue
            rel=name if not rel_root else rel_root.replace("\\","/")+"/"+name
            files[rel]={"mtime":float(st.st_mtime),"size":int(st.st_size)}
            if len(files)>=5000: break
        if len(files)>=5000: break
    ok(files=files)
elif op=="git":
    args=req.get("args") or []
    maxb=int(req.get("max_bytes") or 1500000)
    try:
        p=subprocess.run(["git"]+list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        data=p.stdout[:maxb]
        ok(status=int(p.returncode), data_b64=base64.b64encode(data).decode("ascii"))
    except Exception:
        err("unreadable")
else:
    err("unreadable")
"""#
}
