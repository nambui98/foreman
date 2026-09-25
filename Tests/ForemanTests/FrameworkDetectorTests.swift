import Testing
@testable import Foreman

struct FrameworkDetectorTests {
    @Test func recognisesCommonDevServers() {
        let cases: [([String], String, String?)] = [
            (["node", "/app/node_modules/next/dist/bin/next", "dev"], "node", "Next.js"),
            (["next-server (v15.2.0)"], "next-server", "Next.js"),
            (["node", "/app/node_modules/.bin/vite", "--port", "5173"], "node", "Vite"),
            (["node", "/app/node_modules/vite/bin/vite.js"], "node", "Vite"),
            (["bun", "run", "astro", "dev"], "bun", "Astro"),
            (["node", "/app/node_modules/nuxi/bin/nuxi.mjs", "dev"], "node", "Nuxt"),
            (["python3", "manage.py", "runserver", "8000"], "Python", "Django"),
            (["/venv/bin/python", "/venv/bin/uvicorn", "main:app", "--reload"], "Python", "FastAPI"),
            (["ruby", "bin/rails", "server"], "ruby", "Rails"),
            (["node", "/app/node_modules/expo/bin/cli", "start"], "node", "Expo"),
            (["node", "/app/node_modules/.bin/tsx", "watch", "src/index.ts"], "node", "tsx"),
            (["node", "/app/apps/native/node_modules/.bin/expo", "run:ios"], "node", "Expo"),
            (["node", "/Users/me/.npm/_npx/x/node_modules/.bin/next-devtools-mcp"], "node", "MCP"),
            (["node", "/Users/me/.npm/_npx/x/node_modules/.bin/shadcn", "mcp"], "node", "MCP"),
            (["node", "packages/mcp/dist/index.js"], "node", "MCP"),
            (["node", "/Users/me/.npm/_npx/x/node_modules/.bin/serve", ".", "-l", "3333"], "node", "serve"),
        ]
        for (argv, name, expected) in cases {
            #expect(FrameworkDetector.detect(arguments: argv, name: name) == expected, "\(argv)")
        }
    }

    @Test func plainRuntimesStayUnlabelled() {
        #expect(FrameworkDetector.detect(arguments: ["bun", "src/index.ts"], name: "bun") == nil)
        #expect(FrameworkDetector.detect(arguments: ["node", "server.js"], name: "node") == nil)
        #expect(FrameworkDetector.detect(arguments: [], name: "postgres") == nil)
    }
}

struct RepositoryTests {
    @Test func nameAndSubpath() {
        let repo = GitBranch.Repository(root: "/Users/me/orca/projects/Zunera", branch: "main")
        #expect(repo.name == "Zunera")
        #expect(repo.subpath(of: "/Users/me/orca/projects/Zunera/apps/server") == "apps/server")
        #expect(repo.subpath(of: "/Users/me/orca/projects/Zunera") == nil)
        #expect(repo.subpath(of: "/Users/me/orca/projects/ZuneraOther") == nil)
    }
}
