# frozen_string_literal: true

# Offline check that every SharedValues::<NAME> a Fastfile references is defined by the installed fastlane.
# An undefined constant raises NameError inside a lane, before any `||` fallback runs.
# Usage: bundle exec ruby scripts/check-fastfile-shared-values.rb [Fastfile path]
# Exit codes: 0 all resolve, 1 at least one is undefined, 2 usage or unreadable file.
# Makes no network call and needs no credentials; run it through the project-local Bundler path.

require "fastlane"

def undefined_shared_values(source)
  Fastlane.load_actions
  names = source.scan(/SharedValues::([A-Z][A-Z0-9_]*)/).flatten.uniq.sort
  names.reject { |name| Fastlane::Actions::SharedValues.const_defined?(name) }
end

def main(argv)
  path = argv.fetch(0, File.expand_path("../fastlane/Fastfile", __dir__))
  unless File.file?(path)
    warn "Fastfile not found at #{path} — pass its path as the first argument"
    return 2
  end
  missing = undefined_shared_values(File.read(path))
  unless missing.empty?
    warn "Undefined fastlane SharedValues in #{path}: #{missing.join(', ')} — use a constant defined by the installed fastlane (for the gym package path, PKG_OUTPUT_PATH)"
    return 1
  end
  puts "ok: every SharedValues constant in #{path} is defined"
  0
end

exit(main(ARGV)) if $PROGRAM_NAME == __FILE__
