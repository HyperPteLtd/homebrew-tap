cask "hyper-vpn" do
  version "1.0.0"
  sha256 "0a469127127358239272e01458149d6de0932fda38fea7fa40eb359f01dda19f"

  url "https://dl.hypervpn.app/ladder/macos/1/0a4691271273/Hyper%20VPN_#{version}_arm64.dmg"
  name "Hyper VPN"
  desc "VPN client by Hyper Network"
  homepage "https://hypervpn.app/"

  livecheck do
    url "https://hypervpn.app/v1/public/app/latest?platform=macos"
    strategy :json do |json|
      json.dig("data", "version_name")
    end
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Hyper VPN.app"

  uninstall launchctl: "com.hypernetsg.helper-service",
            quit:      "com.hypernetsg",
            delete:    [
              "/Library/LaunchDaemons/com.hypernetsg.helper-service.plist",
              "/Library/PrivilegedHelperTools/com.hypernetsg.helper-service.bundle",
            ]

  zap trash: [
    "~/Library/Application Support/com.hypernetsg",
    "~/Library/Caches/com.hypernetsg",
    "~/Library/Containers/com.hypernetsg.Extensions",
    "~/Library/Group Containers/3YNVW8CLGX.group.app.com.hypernetsg",
    "~/Library/HTTPStorages/com.hypernetsg",
    "~/Library/Logs/com.hypernetsg",
    "~/Library/Preferences/com.hypernetsg.plist",
    "~/Library/Saved Application State/com.hypernetsg.savedState",
    "~/Library/WebKit/com.hypernetsg",
  ]
end
