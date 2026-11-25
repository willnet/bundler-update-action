require "json"
require "net/http"
require "pathname"
require "rubygems"

module BundlerUpdate
  module_function

  FOOTER = /^BUNDLED WITH\r?\n[ \t]+([0-9][0-9a-zA-Z.\-]*)[ \t]*\r?$/

  def compatible?(version, requirements)
    Gem::Requirement.new(*requirements.to_s.split(",").map(&:strip)).satisfied_by?(version)
  end

  def select_version(releases, current, policy, ruby: Gem.ruby_version, rubygems: Gem.rubygems_version)
    constraints = case policy
                  when "latest" then [">= 0"]
                  when "same-major" then ["~> #{current.segments.first}.0"]
                  else policy.split(",", -1).map(&:strip)
                  end
    raise "Empty bundler-version" if constraints.empty? || constraints.any?(&:empty?)
    requirement = Gem::Requirement.new(*constraints)
    releases.map do |release|
      version = Gem::Version.new(release.fetch("number"))
      next if release.fetch("prerelease") || version <= current || !requirement.satisfied_by?(version)
      next unless compatible?(ruby, release.fetch("ruby_version"))
      next unless compatible?(rubygems, release.fetch("rubygems_version"))
      version
    end.compact.max
  end

  def protected_content(lockfile)
    lockfile.sub(FOOTER, "").sub(/^PLATFORMS\r?\n(?:  [^\r\n]+\r?\n)+/, "")
  end

  def update_lockfile(target)
    original = File.binread("Gemfile.lock")
    command = target >= Gem::Version.new("2.6") ? "lock" : "update"
    success = system({"BUNDLE_GEMFILE" => File.absolute_path("Gemfile")}, "bundle", "_#{target}_", command, "--bundler=#{target}")
    raise "Bundler could not update Gemfile.lock" unless success
    result = File.binread("Gemfile.lock")
    return false if result == original
    unless result[FOOTER, 1] == target.to_s && protected_content(result) == protected_content(original)
      raise "Bundler changed content outside BUNDLED WITH and PLATFORMS or recorded an unexpected version"
    end
    true
  rescue StandardError
    File.binwrite("Gemfile.lock", original) if original
    raise
  end

  def published_versions
    response = Net::HTTP.get_response(URI("https://rubygems.org/api/v1/versions/bundler.json"))
    response.value
    JSON.parse(response.body)
  end

  def run
    file = Pathname.new("Gemfile.lock")
    raise "Missing Gemfile.lock in #{Dir.pwd}" unless file.file?
    root = IO.popen(["git", "rev-parse", "--show-toplevel"], &:read).delete_suffix("\n")
    raise "Cannot locate the checkout containing Gemfile.lock" unless $?.success?
    repository = Pathname.new(root).realpath
    checkout = repository.relative_path_from(Pathname.new(ENV.fetch("GITHUB_WORKSPACE")).realpath)
    raise "Checkout must be inside GITHUB_WORKSPACE" if checkout.each_filename.first == ".."
    raise "Checkout path contains a line break" if root.match?(/[\r\n]/)
    raise "Gemfile.lock must not be a symlink" if file.symlink?
    relative = file.realpath.relative_path_from(repository).to_s
    if relative.match?(/[,\r\n]/)
      raise "create-pull-request cannot accept commas or line breaks in the lockfile path: #{relative.inspect}"
    end
    raw = file.binread[FOOTER, 1] or raise "Missing BUNDLED WITH version in #{relative}"
    current = Gem::Version.new(raw)
    target = select_version(published_versions, current, ENV.fetch("REQUIREMENT"))
    updated = false
    if target
      unless Gem::Specification.find_all_by_name("bundler", target.to_s).any?
        system("gem", "install", "bundler", "--version", target.to_s, "--no-document",
               "--clear-sources", "--source", "https://rubygems.org", exception: true)
      end
      updated = update_lockfile(target)
    end
    File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |out|
      out.puts "updated=#{updated}", "previous-version=#{raw}", "current-version=#{updated ? target : raw}", "repository=./#{checkout}/", "lockfile=#{relative}"
    end
  end
end

BundlerUpdate.run if $PROGRAM_NAME == __FILE__
