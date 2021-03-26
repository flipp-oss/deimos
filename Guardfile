# frozen_string_literal: true

require 'generators/deimos/schema_model_generator'
require 'deimos/config/configuration'

# A sample Guardfile
# More info at https://github.com/guard/guard#readme

# guard :rspec do
#   watch(%r{^spec/.+_spec\.rb$})
#   watch(%r{^lib/(.+)\.rb$})     { |m| "spec/lib/#{m[1]}_spec.rb" }
#   watch('spec/spec_helper.rb')  { 'spec' }
#
#   # Rails example
#   watch(%r{^app/(.+)\.rb$})                           { |m| "spec/#{m[1]}_spec.rb" }
#   watch(%r{^app/(.*)(\.erb|\.haml|\.slim)$})          { |m| "spec/#{m[1]}#{m[2]}_spec.rb" }
#   watch(%r{^app/controllers/(.+)_(controller)\.rb$})  { |m| ["spec/routing/#{m[1]}_routing_spec.rb", "spec/#{m[2]}s/#{m[1]}_#{m[2]}_spec.rb", "spec/acceptance/#{m[1]}_spec.rb"] }
#   watch(%r{^spec/support/(.+)\.rb$})                  { 'spec' }
#   watch('config/routes.rb')                           { 'spec/routing' }
# end
#
# guard :rubocop do
#   watch(/.+\.rb$/)
#   watch(%r{(?:.+/)?\.rubocop\.yml$}) { |m| File.dirname(m[0]) }
# end

run = proc do
  Deimos::Generators::SchemaModelGenerator.start([])
end

yield_commands = {
  run_all: run,
  run_on_additions: run,
  run_on_modifications: run
}
guard :yield, yield_commands do
  watch(%r{^#{Deimos.config.schema.path}/*})
  watch("#{Deimos.config.schema.path}/*")
  # add the file path HERE
end
