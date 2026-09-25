import Foundation

/// Names the dev tool behind a process from its argv, e.g. `node …/next/dist/bin/next dev` → Next.js.
enum FrameworkDetector {
    /// Checked in order; the first match wins, so specific tools come before the runtimes they use.
    private static let rules: [(name: String, needles: [String])] = [
        // MCP servers first: their package names often mention a framework (next-devtools-mcp).
        ("MCP", ["-mcp", " mcp", "/mcp/", "mcp-server", "modelcontextprotocol"]),
        ("Next.js", ["next-server", "/next/dist/", "next dev", "next start"]),
        ("Nuxt", ["nuxi", "/nuxt/", "nuxt dev"]),
        ("Astro", ["/astro/", "astro dev"]),
        ("Remix", ["remix dev", "/@remix-run/"]),
        ("SvelteKit", ["svelte-kit", "@sveltejs/kit"]),
        ("Gatsby", ["gatsby develop", "/gatsby/"]),
        ("Angular", ["ng serve", "/@angular/cli/"]),
        ("Storybook", ["storybook"]),
        ("Expo", ["expo start", "expo run:", "/expo/bin/", "/.bin/expo", "@expo/cli"]),
        ("Metro", ["react-native start", "/metro/"]),
        ("Vite", ["/vite/bin/", "vite.js", "/.bin/vite", " vite"]),
        ("Webpack", ["webpack-dev-server", "webpack serve"]),
        ("Wrangler", ["wrangler"]),
        ("NestJS", ["nest start", "/@nestjs/cli/"]),
        ("Django", ["manage.py runserver", "django"]),
        ("FastAPI", ["uvicorn", "fastapi"]),
        ("Flask", ["flask run", "/flask"]),
        ("Rails", ["rails server", "rails s", "puma"]),
        ("Laravel", ["artisan serve"]),
        ("Hugo", ["hugo server"]),
        ("Jekyll", ["jekyll serve"]),
        ("tsx", ["/tsx/", "/.bin/tsx"]),
        ("serve", ["/.bin/serve "]),
        ("nodemon", ["nodemon"]),
    ]

    static func detect(arguments: [String], name: String) -> String? {
        let argv = " " + arguments.joined(separator: " ").lowercased()
        let haystack = argv + " " + name.lowercased()
        return rules.first { rule in rule.needles.contains { haystack.contains($0.lowercased()) } }?.name
    }
}
