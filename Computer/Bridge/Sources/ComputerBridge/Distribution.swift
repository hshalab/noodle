import Foundation

/// Computer releases never use GitHub's repository-wide `latest` release,
/// which belongs to standard Noodle.
public enum ComputerDistribution {
    public static let documentation = URL(string: "https://github.com/pdparchitect/noodle/tree/main/Computer#build-and-run")!
    public static let feed = URL(string: "https://github.com/pdparchitect/noodle/releases/download/computer-latest/appcast.xml")!
}
