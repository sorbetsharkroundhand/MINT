import Foundation

let expectedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? "missing"
print("env home: \(expectedHome)")
print("resolved home: \(NSHomeDirectory())")
print("bundle ID: \(Bundle.main.bundleIdentifier ?? "missing")")
print("mode: \(CommandLine.arguments.last ?? "missing")")
if CommandLine.arguments.last == "seed" {
    UserDefaults.standard.set(true, forKey: "mint.initialModelConfirmed")
    UserDefaults.standard.set(false, forKey: "completion.enabled")
    print("synchronize: \(UserDefaults.standard.synchronize())")
}
let confirmed = UserDefaults.standard.object(forKey: "mint.initialModelConfirmed") as? Bool
let enabled = UserDefaults.standard.object(forKey: "completion.enabled") as? Bool
print("model confirmed: \(String(describing: confirmed))")
print("completion enabled: \(String(describing: enabled))")
if confirmed == true, enabled == false, CommandLine.arguments.last == "read" {
    try Data().write(to: URL(fileURLWithPath: expectedHome).appendingPathComponent("probe-passed"))
}
