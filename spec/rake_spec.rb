# frozen_string_literal: true

require 'rake'
require 'rails'
Rails.logger = Logger.new(STDOUT)
load("#{__dir__}/../lib/tasks/deimos.rake")

if Rake.application.lookup(:environment).nil?
  Rake::Task.define_task(:environment)
end

describe 'Rakefile' do
  it 'should start listeners' do
    expect(Karafka::Server).to receive(:run)
    Rake::Task['deimos:start'].invoke
  end
end
