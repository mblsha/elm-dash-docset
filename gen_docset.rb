#!/usr/bin/env ruby

require 'fileutils'
require 'pp'

require 'rubygems'
require 'curb'
require 'json'

all_packages = Curl.get("http://library.elm-lang.org/all-packages")
all_packages_dict = JSON::Ext::Parser.new(all_packages.body_str).parse()
all_packages_dict.each do |package|
  name = package["name"]
  version = package["versions"].first

  package_path = "docroot/#{name}/#{version}"
  FileUtils::mkdir_p package_path

  documentation_path = "#{package_path}/documentation.json"
  next if File.exist? documentation_path

  documentation = Curl.get("http://library.elm-lang.org/packages/#{name}/#{version}/documentation.json")
  File.open(documentation_path, "wb") do |f|
    f.write documentation.body_str
  end

  break
end
