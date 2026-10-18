import Foundation
import Testing

@testable import Xmac

@Suite struct UpdateAndDiskTests {
  @Test func teamSignedAppPinsTeamAndBundleIdentifier() {
    #expect(UpdateTrust.policy(runningTeamID: "ABCDE12345") == .teamPinned("ABCDE12345"))
    #expect(UpdateTrust.requirement(teamID: "ABCDE12345")
      == "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"")
    let policy = UpdateTrust.Policy.teamPinned("ABCDE12345")
    #expect(UpdateTrust.isAcceptable(policy: policy, runningBundleID: "vn.xmac.app",
      candidateBundleID: "vn.xmac.app", candidateMeetsTeamRequirement: true))
    // A foreign or ad-hoc signature fails the team requirement even with the right bundle identifier.
    #expect(!UpdateTrust.isAcceptable(policy: policy, runningBundleID: "vn.xmac.app",
      candidateBundleID: "vn.xmac.app", candidateMeetsTeamRequirement: false))
    #expect(!UpdateTrust.isAcceptable(policy: policy, runningBundleID: "vn.xmac.app",
      candidateBundleID: "com.evil.app", candidateMeetsTeamRequirement: true))
  }

  @Test func adHocAppStillRequiresIdenticalBundleIdentifier() {
    #expect(UpdateTrust.policy(runningTeamID: nil) == .bundleIdentifierOnly)
    #expect(UpdateTrust.policy(runningTeamID: "") == .bundleIdentifierOnly)
    #expect(UpdateTrust.isAcceptable(policy: .bundleIdentifierOnly, runningBundleID: "vn.xmac.app",
      candidateBundleID: "vn.xmac.app", candidateMeetsTeamRequirement: false))
    #expect(!UpdateTrust.isAcceptable(policy: .bundleIdentifierOnly, runningBundleID: "vn.xmac.app",
      candidateBundleID: "other.app", candidateMeetsTeamRequirement: false))
    #expect(!UpdateTrust.isAcceptable(policy: .bundleIdentifierOnly, runningBundleID: nil,
      candidateBundleID: nil, candidateMeetsTeamRequirement: false))
  }

  @Test func malformedTeamIdentifierFailsClosed() {
    #expect(UpdateTrust.policy(runningTeamID: "x\" or true") == nil)
    #expect(UpdateTrust.policy(runningTeamID: "short") == nil)
  }

  @Test func ntfs3gMountAllowsUserAccessAndSetsVolumeName() {
    let args = NTFSMountHelper.ntfs3gArguments(binary: "/opt/homebrew/bin/ntfs-3g", deviceNode: "/dev/disk4s1",
      mountPoint: "/Volumes/Xmac_disk4s1", volumeName: "Du lieu,\n'x'")
    #expect(args == ["/opt/homebrew/bin/ntfs-3g", "/dev/disk4s1", "/Volumes/Xmac_disk4s1",
      "-o", "allow_other,local", "-o", "volname=Du lieu'x'"])
    // The label stays a single shell word even with quotes in it.
    #expect(POSIXShell.join(args).hasSuffix("'volname=Du lieu'\"'\"'x'\"'\"''"))
    #expect(NTFSMountHelper.ntfs3gArguments(binary: "b", deviceNode: "d", mountPoint: "m", volumeName: ",,")
      == ["b", "d", "m", "-o", "allow_other,local"])
  }

  @Test func staleScanGenerationsAreDropped() {
    var generation = ScanGeneration()
    let first = generation.advance()
    let second = generation.advance()
    #expect(!generation.isCurrent(first))
    #expect(generation.isCurrent(second))
  }
}
