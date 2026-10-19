import Foundation

/// The page shown when the site can't be reached (offline, DNS failure, etc.).
enum ErrorPage {
    static func html(title: String, message: String, retryURL: URL) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body { font: 14px -apple-system, system-ui, sans-serif; display: grid; place-items: center;
                 height: 100vh; margin: 0; background: Canvas; color: CanvasText; }
          main { max-width: 440px; text-align: center; padding: 24px; }
          h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; }
          p { opacity: 0.7; line-height: 1.45; margin: 0 0 20px; }
          a { display: inline-block; padding: 6px 16px; border-radius: 6px; background: AccentColor;
              color: white; text-decoration: none; font-weight: 500; }
        </style>
        </head>
        <body>
        <main>
          <h1>\(escape(title))</h1>
          <p>\(escape(message))</p>
          <a href="\(escape(retryURL.absoluteString))">Try Again</a>
        </main>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
