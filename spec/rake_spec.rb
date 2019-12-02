# frozen_string_literal: true

require 'rake'
require 'rails'
Rails.logger = Logger.new(STDOUT)
load("#{__dir__}/../lib/tasks/deimos.rake")

if Rake.application.lookup(:environment).nil?
  Rake::Task.define_task(:environment)
end

describe 'Rakefile' do # rubocop:disable RSpec/DescribeClass
  it 'should start listeners' do
    runner = instance_double(Phobos::CLI::Runner)
    expect(Phobos::CLI::Runner).to receive(:new).and_return(runner)
    expect(runner).to receive(:run!)
    Rake::Task['deimos:start'].invoke
  end
end
