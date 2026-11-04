import Foundation

/// A screenshot or recording the operator saved from a dashboard view in Paddock (backlog doc
/// Browser). The dashboard hands it to the web view as a download; Paddock puts it in the
/// sandbox instead of on the Mac, under `folder`, and tells the agent whose page it is: a
/// session's agent through a note it reads on its next command, a show tab's in the tab's history.
public enum BrowserCapture {
    public static let folder = "/tmp/paddock-browser/captures"

    public enum Kind: String, Sendable, Equatable {
        case screenshot, recording
    }

    /// Whose page it shows.
    public enum Owner: Sendable, Equatable {
        case session(String)
        case show(String)
    }

    public static func kind(of fileName: String) -> Kind {
        ["webm", "mp4", "mov"].contains((fileName as NSString).pathExtension.lowercased()) ? .recording : .screenshot
    }

    /// The name in the sandbox: the dashboard's suggestion reduced to letters, digits, `.`, `_`,
    /// `-` (it comes from the sandbox's page), after a timestamp so captures never overwrite each
    /// other.
    public static func fileName(suggested: String, at date: Date) -> String {
        let base = String((suggested as NSString).lastPathComponent.unicodeScalars.map {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) ? Character($0) : "-"
        }).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        let stamp = Int(date.timeIntervalSince1970 * 1000)
        return "\(stamp)-\(base.isEmpty ? "capture" : String(base.prefix(80)))"
    }

    /// The sbx commands, in order: make the folder, copy the file in, tell the agent. Nil for an
    /// owner Paddock does not know.
    public static func commands(sandbox: String, localFile: String, fileName: String, owner: Owner) -> [[String]]? {
        let destination = folder + "/" + fileName
        let kind = kind(of: fileName).rawValue
        let tell: [String]
        switch owner {
        case .session(let session):
            guard BrowserActivity.isSessionName(session) else { return nil }
            tell = ["exec", sandbox, "paddock-browser-watch", "--captured", session, destination, kind]
        case .show(let id):
            guard BrowserShow.isShowID(id) else { return nil }
            tell = ["exec", sandbox, "paddock", "--operator", id, kind, destination]
        }
        return [["exec", sandbox, "mkdir", "-p", folder], ["cp", localFile, sandbox + ":" + destination], tell]
    }

    /// JavaScript for the Playwright tab: the session of the page selected in this view of the
    /// dashboard (the option marked selected, in the section labelled "Session NAME"), or null.
    /// Depends on the dashboard's markup like `BrowserActivity.selectScript`.
    public static let selectedSessionScript = """
        (function () {
          var option = document.querySelector('[role="option"][aria-selected="true"]');
          var section = option ? option.closest('[aria-label^="Session "]') : null;
          return section ? section.getAttribute('aria-label').slice('Session '.length) : null;
        })();
        """
}
