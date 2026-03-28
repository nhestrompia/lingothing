cask "lingothing" do
  version "0.1.33"
  sha256 "3a5e53d7fbef322b3147beef88550d11a05665d1af0af0e7c266958fbe06324c"

  url "https://github.com/nhestrompia/lingothing/releases/download/v#{version}/LingoThing-#{version}.app.zip"
  name "LingoThing"
  desc "Menu bar language practice app"
  homepage "https://github.com/nhestrompia/lingothing"

  depends_on macos: ">= :sonoma"

  app "LingoThing.app"

  zap trash: [
    "~/Library/Application Support/LingoThing",
    "~/Library/Preferences/com.lingothing.app.plist",
  ]
end
