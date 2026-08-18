require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name            = "RNMdList"
  s.version         = package["version"]
  s.summary         = package["description"]
  s.license         = "MIT"
  s.authors         = { "RNApp" => "dev@rnapp.local" }
  s.homepage        = "https://example.com/react-native-md-list"
  s.platforms       = { :ios => "15.1" }
  s.source          = { :git => "https://example.com/react-native-md-list.git", :tag => "#{s.version}" }

  s.source_files    = "ios/**/*.{h,m,mm,swift}"
  s.requires_arc    = true
  s.swift_version   = "5.9"

  # Pulls in React-Core, Fabric, codegen'd RNMdListSpec, etc.
  install_modules_dependencies(s)
end
