cask "lingothing" do
  version "0.1.32"
  sha256 "3a817d857dc6e93ecd6928fbbff62d6484861ac2470d6f7f1656db0db1736eaa"

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
