#!/usr/bin/env ruby

require 'fileutils'
require 'pp'

require 'rubygems'
require 'curb'
require 'json'
require 'rubysh'

ROOT = File.absolute_path(File.join(File.dirname(__FILE__), "docroot"))

def build_elm_files
  Dir.chdir(File.join(ROOT, "..", "package.elm-lang.org")) do
    { "frontend/Page/Package.elm" => "artifacts/Page-Package.js",
      "frontend/Page/Module.elm" => "artifacts/Page-Module.js"
    }.each do |pair|
      js_output = File.join(ROOT, pair[1])
      cmd = Rubysh('elm-make', pair[0], '--yes', "--output=#{js_output}")
      cmd.run
    end
  end
end

build_elm_files
exit 1

all_packages = Curl.get("http://library.elm-lang.org/all-packages")
all_packages_dict = JSON::Ext::Parser.new(all_packages.body_str).parse()
all_packages_dict.each do |package|
  name = package["name"]
  version = package["versions"].first

  package_path = File.join(ROOT, "packages", name, version)
  FileUtils::mkdir_p package_path

  documentation_path = File.join(package_path, "documentation.json")
  # next if File.exist? documentation_path

  documentation = Curl.get("http://library.elm-lang.org/packages/#{name}/#{version}/documentation.json")
  File.open(documentation_path, "wb") do |f|
    f.write documentation.body_str
  end

  break
end
