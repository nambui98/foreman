import Testing
@testable import PortBar

struct FormattersTests {
    @Test func cpuFormatting() {
        #expect(Formatters.cpu(nil) == "—")
        #expect(Formatters.cpu(0.25) == "0.2%" || Formatters.cpu(0.25) == "0.3%")
        #expect(Formatters.cpu(142.6) == "143%")
    }

    @Test func pathAbbreviation() {
        #expect(Formatters.abbreviatePath("/Users/me/Workspace/app", home: "/Users/me") == "~/Workspace/app")
        #expect(Formatters.abbreviatePath("/Users/me", home: "/Users/me") == "~")
        #expect(Formatters.abbreviatePath("/Users/meow/x", home: "/Users/me") == "/Users/meow/x")
        #expect(Formatters.abbreviatePath("/", home: "/Users/me") == nil)
        #expect(Formatters.abbreviatePath(nil) == nil)
    }

    @Test func memoryFormattingMissingValue() {
        #expect(Formatters.memory(nil) == "—")
        #expect(!Formatters.memory(50 * 1024 * 1024).isEmpty)
    }
}
