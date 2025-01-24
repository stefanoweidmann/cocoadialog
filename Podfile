minium_deployment_target = '10.13' # Required for XCode 16
platform :osx, minium_deployment_target
inhibit_all_warnings!

target 'cocoadialog' do
  pod 'GRMustache', '~> 7.3.2'
  pod 'Masonry', '~> 1.1.0'
  pod 'TSMarkdownParser', '~> 2.1.3'
end

class ::Pod::Generator::Acknowledgements
  def header_text
    "\nThe following third party libraries are so awesome, you'll just have to check them out to see how badass they are! Thank you for coding amazing tools and letting this project use them!\n\n\n" +
    "## CocoaPods\n\n[CocoaPods](https://cocoapods.org) is a dependency manager for Swift and Objective-C Cocoa projects.\n\nThe MIT License (MIT): \n\nhttps://github.com/CocoaPods/CocoaPods/blob/master/LICENSE\n\n"
  end
  def footnote_text
    ""
  end
end

post_install do | installer |
  installer.pods_project.targets.each do |target|
#    target.build_configurations.each do |config|
#      config.build_settings['GCC_PREFIX_HEADER'] = "$(SDKROOT)/System/Library/Frameworks/Cocoa.framework/Headers/Cocoa.h"
#    end

    # Only match Pod targets, not Pods used inside the targets.
    next if !target.name.match(/^Pods-/)

    root = Pathname.new(File.dirname(__FILE__))

    # Generated file.
    dir = installer.sandbox.target_support_files_root.relative_path_from(root).to_s + "/" + target.name
    filename = target.name + "-acknowledgements.markdown"
    file = dir + "/" + filename

    # New file.
    newDir = "Resources"
    newFilename = "Acknowledgements.md"
    newFile = newDir + "/" + newFilename

    # Check if generated file exists and then copy it.
    puts "    - Checking if \"" + target.name + "\" has \"" + file + "\"..."
    if (File.file?(file))
        puts "      - Copying \"" + filename + "\" -> \"" + newFile + "\"..."
        FileUtils.cp_r(file, newFile, :remove_destination => true)
    end
  end

  # set minimum deployment target because OSX 10.8 is not supported by newer XCode any longer
  # https://stackoverflow.com/questions/77139617/clang-error-sdk-does-not-contain-libarclite-at-the-path
  # https://developer.apple.com/support/xcode/
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = minium_deployment_target
    end
  end
end
