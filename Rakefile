# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :release do
  def run_rubocop
    Bundler.with_unbundled_env do
      sh "RUBOCOP_CACHE_ROOT=.rubocop_cache rubocop --no-server"
    end
  end

  desc "Run release preflight checks (unit/integration specs, RuboCop, frontend tests)"
  task :preflight do
    sh "bundle exec rspec --exclude-pattern spec/e2e/**/*_spec.rb"
    run_rubocop
    sh "npm --prefix frontend test"
  end

  desc "Run release preflight checks including E2E specs"
  task :preflight_full do
    sh "bundle exec rspec"
    run_rubocop
    sh "npm --prefix frontend test"
  end

  desc "Build the gem package"
  task :build do
    sh "gem build vizcore.gemspec"
  end

  desc "Verify packaged gem contents against release policy"
  task verify_package: :build do
    sh "ruby scripts/verify_gem_contents.rb"
  end

  desc "Run complete release verification pipeline"
  task verify: %i[preflight verify_package]
end
