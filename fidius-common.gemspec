# encoding: utf-8
$:.push File.expand_path("../lib", __FILE__)
require "fidius-common/version"

Gem::Specification.new do |s|
  s.name        = "fidius-common"
  s.version     = FIDIUS::Common::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Dominik Menke", "Bernd Katzmarski"]
  s.email       = ["dmke+fidicom@tzi.org", "bkatzm+fidicom@tzi.org"]
  s.homepage    = ""
  s.summary     = "Common useful libraries and methods for the FIDIUS C&C server, the FIDIUS 'architecture' and maybe other components."
  s.description = s.summary + "\n\nThese gem and its classes/modules/methods are meant to run stand-alone, e.g. in non-FIDIUS components."

  s.rubyforge_project = ""

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_development_dependency 'simplecov', '>= 0.4.0'
  s.add_runtime_dependency 'activesupport', '>= 3.0.0'
  s.add_runtime_dependency 'activerecord', '>= 3.0.0'
  s.add_runtime_dependency 'sqlite3'
  s.add_runtime_dependency 'highline'

  s.rdoc_options << '--title' << s.name <<
                    '--main'  << 'README.md' << '--show-hash' <<
                    `git ls-files -- lib/*`.split("\n") <<
                    'README.md' << 'LICENSE' << 'CREDITS.md'
end
