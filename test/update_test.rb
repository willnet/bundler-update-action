require_relative "../scripts/update"
require "tmpdir"

def release(number, ruby = ">= 0", rubygems = ">= 0")
  {"number" => number, "ruby_version" => ruby, "rubygems_version" => rubygems,
   "prerelease" => Gem::Version.new(number).prerelease?}
end

catalog = [release("2.6.8"), release("2.6.9"), release("2.7.1"), release("4.0.0", ">= 3, < 4", ">= 3, < 4"),
           release("4.1.0", ">= 3, < 3.3"), release("4.2.0", ">= 3", ">= 3, < 3.5"), release("5.0.pre")]
[
  ["2.6.8", "~> 2.6.0", "2.6.9"],
  ["2.6.8", "same-major", "2.7.1"],
  ["2.6.8", "latest", "4.0.0"],
  ["2.6.8", ">= 2.6, < 2.7", "2.6.9"],
  ["2.7.1", "same-major", nil],
  ["4.0.0", "latest", nil],
  ["2.7.1", "= 2.6.9", nil]
].each do |current, policy, expected|
  actual = BundlerUpdate.select_version(catalog, Gem::Version.new(current), policy,
                                        ruby: Gem::Version.new("3.3"), rubygems: Gem::Version.new("3.5"))
  raise "#{current} #{policy}: expected #{expected.inspect}, got #{actual.inspect}" unless actual&.to_s == expected
end

target = Gem::Version.new(ENV.fetch("TEST_BUNDLER"))
Dir.mktmpdir do |workspace|
  repository = File.realpath(workspace) + "/checkout"
  system("git", "init", "--quiet", repository, exception: true)
  project = "日本語+api@[v1]"
  Dir.mkdir("#{repository}/#{project}")
  Dir.chdir("#{repository}/#{project}") do
    begin
      BundlerUpdate.run
      raise "Expected missing lockfile error"
    rescue RuntimeError => error
      raise unless error.message.start_with?("Missing Gemfile.lock")
    end
    File.write("demo.gemspec", <<~SPEC)
      Gem::Specification.new do |s|
        s.name = "demo"
        s.version = "1.2.3"
        s.summary = "Integration fixture"
        s.authors = ["Test"]
      end
    SPEC
    File.write("Gemfile", "gemspec\n")
    system("bundle", "_#{target}_", "lock", "--local", exception: true)
    original = File.binread("Gemfile.lock")
    raise "Missing locked dependency" unless original.include?("    demo (1.2.3)")
    File.binwrite("Gemfile.lock", original.sub(BundlerUpdate::FOOTER, "BUNDLED WITH\n   2.2.0"))
    BundlerUpdate.define_singleton_method(:published_versions) { [release(target.to_s)] }
    ENV.update("GITHUB_WORKSPACE" => workspace, "GITHUB_OUTPUT" => "#{workspace}/output", "REQUIREMENT" => "latest")
    BundlerUpdate.run
    expected = ["updated=true", "previous-version=2.2.0", "current-version=#{target}", "repository=./checkout/", "lockfile=#{project}/Gemfile.lock"]
    raise "Incorrect update outputs" unless File.readlines(ENV["GITHUB_OUTPUT"], chomp: true) == expected
    BundlerUpdate.run
    unchanged = ["updated=false", "previous-version=#{target}", "current-version=#{target}", "repository=./checkout/", "lockfile=#{project}/Gemfile.lock"]
    raise "Incorrect repeat-run outputs" unless File.readlines(ENV["GITHUB_OUTPUT"], chomp: true).last(unchanged.size) == unchanged
    raise "Unexpected diff" unless File.binread("Gemfile.lock") == original

    old_lock = original.sub(BundlerUpdate::FOOTER, "BUNDLED WITH\n   2.2.0")
    File.binwrite("Gemfile.lock", old_lock)
    File.write("demo.gemspec", File.read("demo.gemspec").sub("1.2.3", "2.0.0"))
    begin
      BundlerUpdate.update_lockfile(target)
      raise "Expected dependency change to be rejected"
    rescue RuntimeError => error
      raise unless error.message.start_with?("Bundler changed content")
    end
    raise "Expected original lockfile to be restored" unless File.binread("Gemfile.lock") == old_lock
  end
end
puts "Passed version selection and lockfile checks with Bundler #{target}"
