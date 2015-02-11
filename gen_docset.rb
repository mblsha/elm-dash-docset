#!/usr/bin/env ruby

require 'fileutils'
require 'pp'

require 'rubygems'
require 'erb'
require 'curb'
require 'json'
require 'rubysh'

ROOT = File.absolute_path(File.join(File.dirname(__FILE__), 'docroot'))
package_template = ERB.new(File.read(File.join(ROOT, 'templates', 'package.erb.html')))
module_template = ERB.new(File.read(File.join(ROOT, 'templates', 'module.erb.html')))
$index_array = []

def build_elm_files
  Dir.chdir(File.join(ROOT, '..', 'package.elm-lang.org')) do
    { 'frontend/Page/Package.elm' => 'artifacts/Page-Package.js',
      'frontend/Page/Module.elm' => 'artifacts/Page-Module.js'
    }.each do |pair|
      js_output = File.join(ROOT, pair[1])
      cmd = Rubysh('elm-make', pair[0], '--yes', "--output=#{js_output}")
      cmd.run

      patched_contents = File.read(js_output).gsub(
        '(request.status >= 200 && request.status < 300 ?',
        '((request.status == 0 || (request.status >= 200 && request.status < 300)) ?')
      File.write(js_output, patched_contents)
    end
  end
end

def escape_module(name)
  return name.gsub(/[.]/, '-')
end

def index_module_dict(module_dict, module_index_html_path, section)
  types = {
    'types' => 'Type',
    'aliases' => 'Type',  # Alias?
    'values' => 'Function',
  }

  module_dict[section].each do |i|
    name = i['name']
    $index_array += [{
      'type' => types[section],
      'name' => name,
      'path' => "#{module_index_html_path}##{name}"
    }]
  end
end

def create_index_sql
  sql = []
  sql += ['CREATE TABLE IF NOT EXISTS searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);']
  sql += ['CREATE UNIQUE INDEX IF NOT EXISTS anchor ON searchIndex (name, type, path);']
  $index_array.each do |i|
    name = i['name']
    path = i['path'].gsub(ROOT, '')
    sql += ["INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES (\"#{name}\", \"#{i['type']}\", \"#{path}\");"]
  end
  return sql.join("\n")
end

all_packages = Curl.get('http://library.elm-lang.org/all-packages')
all_packages_dict = JSON::Ext::Parser.new(all_packages.body_str).parse()
all_packages_dict.each do |package|
  name = package['name']
  version = package['versions'].first
  # name = 'elm-lang/core'
  # version = '1.1.0'

  package_path = File.join(ROOT, 'packages', name, version)
  FileUtils::mkdir_p package_path

  $index_array += [{
    'type' => 'Package',
    'name' => name,
    'path' => "#{package_path}/index.html"
  }]

  readme = Curl.get("http://library.elm-lang.org/packages/#{name}/#{version}/README.md")
  if readme.status == '200 OK'
    File.write(File.join(package_path, 'README.md'), readme.body_str)
  end

  documentation_path = File.join(package_path, 'documentation.json')
  # next if File.exist? documentation_path

  documentation = Curl.get("http://library.elm-lang.org/packages/#{name}/#{version}/documentation.json")
  documentation_json = JSON::Ext::Parser.new(documentation.body_str).parse()
  File.open(documentation_path, 'wb') do |f|
    f.write documentation.body_str
  end

  File.open(File.join(package_path, 'index.html'), 'wb') do |f|
    erb_user, erb_name = name.split('/')
    erb_version = version
    f.write package_template.result(binding)
  end

  documentation_json.each do |module_dict|
    module_name = module_dict['name'] #
    module_path = File.join(package_path, escape_module(module_name))
    $index_array += [{
      'type' => 'Module',
      'name' => module_name,
      'path' => "#{module_path}/index.html"
    }]

    FileUtils::mkdir_p(module_path)
    module_index_html_path = File.join(module_path, 'index.html')
    File.open(module_index_html_path, 'wb') do |f|
      erb_user, erb_name = name.split('/')
      erb_version = version
      erb_module_name = module_name
      f.write module_template.result(binding)
    end

    File.open(File.join(module_path, escape_module(module_name) + '.json'), 'wb') do |f|
      f.write JSON.dump(module_dict)
    end

    index_module_dict(module_dict, module_index_html_path, 'aliases')
    index_module_dict(module_dict, module_index_html_path, 'types')
    index_module_dict(module_dict, module_index_html_path, 'values')
  end

  break
end

File.open(File.join(ROOT, 'index.json'), 'wb') do |f|
  f.write JSON.pretty_generate($index_array)
end

build_elm_files

sqlite = Rubysh('sqlite3', File.join(ROOT, 'docSet.dsidx'), Rubysh.<<< create_index_sql)
sqlite.run