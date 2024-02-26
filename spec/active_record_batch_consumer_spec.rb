# frozen_string_literal: true

# Wrapped in a module to prevent class leakage
module ActiveRecordBatchConsumerTest
  describe Deimos::ActiveRecordConsumer, 'Batch Consumer' do
    # Create ActiveRecord table and model
    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.string(:test_id)
        t.string(:part_one)
        t.string(:part_two)
        t.integer(:some_int)
        t.boolean(:deleted, default: false)
        t.string(:bulk_import_id)
        t.timestamps

        t.index(%i(part_one part_two), unique: true)
      end

      # Sample model
      class Widget < ActiveRecord::Base
        validates :test_id, presence: true

        default_scope -> { where(deleted: false) }
      end

      Widget.reset_column_information
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    prepend_before(:each) do
      stub_const('MyBatchConsumer', consumer_class)
      stub_const('ConsumerTest::MyBatchConsumer', consumer_class)
      consumer_class.config[:bulk_import_id_column] = :bulk_import_id # default
    end

    around(:each) do |ex|
      # Set and freeze example time
      travel_to start do
        ex.run
      end
    end

    # Default starting time
    let(:start) { Time.zone.local(2019, 1, 1, 10, 30, 0) }

    # Basic uncompacted consumer
    let(:consumer_class) do
      Class.new(described_class) do
        schema 'MySchema'
        namespace 'com.my-namespace'
        key_config plain: true
        record_class Widget
        compacted false
      end
    end

    # Helper to get all instances, ignoring default scopes
    def all_widgets
      Widget.unscoped.all
    end

    # Helper to publish a list of messages and call the consumer
    def publish_batch(messages)
      keys = messages.map { |m| m[:key] }
      payloads = messages.map { |m| m[:payload] }

      test_consume_batch(MyBatchConsumer, payloads, keys: keys, call_original: true)
    end

    describe 'consume_batch' do
      SCHEMA_CLASS_SETTINGS.each do |setting, use_schema_classes|
        context "with Schema Class consumption #{setting}" do

          before(:each) do
            Deimos.configure do |config|
              config.schema.use_schema_classes = use_schema_classes
              config.schema.use_full_namespace = true
            end
          end

          it 'should handle an empty batch' do
            expect { publish_batch([]) }.not_to raise_error
          end

          it 'should create records from a batch' do
            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } },
                { key: 2,
                  payload: { test_id: 'def', some_int: 4 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'abc', some_int: 3, updated_at: start, created_at: start),
                  have_attributes(id: 2, test_id: 'def', some_int: 4, updated_at: start, created_at: start)
                ]
              )
          end

          it 'should handle deleting a record that doesn\'t exist' do
            publish_batch(
              [
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should handle an update, followed by a delete in the correct order' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should handle a delete, followed by an update in the correct order' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            travel 1.day

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: { test_id: 'abc', some_int: 3 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'abc', some_int: 3, updated_at: Time.zone.now, created_at: Time.zone.now)
                ]
              )
          end

          it 'should handle a double update' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            travel 1.day

            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'def', some_int: 3 } },
                { key: 1,
                  payload: { test_id: 'ghi', some_int: 4 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 1, test_id: 'ghi', some_int: 4, updated_at: Time.zone.now, created_at: start)
                ]
              )
          end

          it 'should handle a double deletion' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should ignore default scopes' do
            Widget.create!(id: 1, test_id: 'abc', some_int: 2, deleted: true)
            Widget.create!(id: 2, test_id: 'def', some_int: 3, deleted: true)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 2,
                  payload: { test_id: 'def', some_int: 5 } }
              ]
            )

            expect(all_widgets).
              to match_array(
                [
                  have_attributes(id: 2, test_id: 'def', some_int: 5)
                ]
              )
          end

          it 'should handle deletes with deadlock retries' do
            allow(Deimos::Utils::DeadlockRetry).to receive(:sleep)
            allow(instance_double(ActiveRecord::Relation)).to receive(:delete_all).and_raise(
              ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')
            ).twice.ordered

            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(all_widgets).to be_empty
          end

          it 'should not delete after multiple deadlock retries' do
            allow(Deimos::Utils::DeadlockRetry).to receive(:sleep)
            allow(instance_double(ActiveRecord::Relation)).to receive(:delete_all).and_raise(
              ActiveRecord::Deadlocked.new('Lock wait timeout exceeded')
            ).exactly(3).times

            Widget.create!(id: 1, test_id: 'abc', some_int: 2)

            publish_batch(
              [
                { key: 1,
                  payload: nil },
                { key: 1,
                  payload: nil }
              ]
            )

            expect(Widget.count).to eq(0)

          end

        end
      end
    end

    describe 'compacted mode' do
      # Create a compacted consumer
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget

          # :no-doc:
          def deleted_query(_records)
            raise 'Should not have anything to delete!'
          end
        end
      end

      it 'should allow for compacted batches' do
        expect(Widget).to receive(:import!).once.and_call_original

        publish_batch(
          [
            { key: 1,
              payload: nil },
            { key: 2,
              payload: { test_id: 'xyz', some_int: 5 } },
            { key: 1,
              payload: { test_id: 'abc', some_int: 3 } },
            { key: 2,
              payload: { test_id: 'def', some_int: 4 } },
            { key: 3,
              payload: { test_id: 'hij', some_int: 9 } }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 3),
              have_attributes(id: 2, test_id: 'def', some_int: 4),
              have_attributes(id: 3, test_id: 'hij', some_int: 9)
            ]
          )
      end
    end

    describe 'compound keys' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config schema: 'MySchemaCompound_key'
          record_class Widget
          compacted false

          # :no-doc:
          def deleted_query(records)
            keys = records.
              map { |m| record_key(m.key) }.
              reject(&:empty?)

            # Only supported on Rails 5+
            keys.reduce(@klass.none) do |query, key|
              query.or(@klass.unscoped.where(key))
            end
          end
        end
      end

      it 'should consume with compound keys' do
        Widget.create!(test_id: 'xxx', some_int: 2, part_one: 'ghi', part_two: 'jkl')
        Widget.create!(test_id: 'yyy', some_int: 7, part_one: 'mno', part_two: 'pqr')

        allow_any_instance_of(MyBatchConsumer).to receive(:key_columns).
          and_return(%w(part_one part_two))

        publish_batch(
          [
            { key: { part_one: 'abc', part_two: 'def' }, # To be created
              payload: { test_id: 'aaa', some_int: 3 } },
            { key: { part_one: 'ghi', part_two: 'jkl' }, # To be updated
              payload: { test_id: 'bbb', some_int: 4 } },
            { key: { part_one: 'mno', part_two: 'pqr' }, # To be deleted
              payload: nil }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(test_id: 'aaa', some_int: 3, part_one: 'abc', part_two: 'def'),
              have_attributes(test_id: 'bbb', some_int: 4, part_one: 'ghi', part_two: 'jkl')
            ]
          )
      end
    end

    describe 'no keys' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config none: true
          record_class Widget
        end
      end

      it 'should handle unkeyed topics' do
        Widget.create!(test_id: 'xxx', some_int: 2)

        publish_batch(
          [
            { payload: { test_id: 'aaa', some_int: 3 } },
            { payload: { test_id: 'bbb', some_int: 4 } },
            { payload: nil } # Should be ignored. Can't delete with no key
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(test_id: 'xxx', some_int: 2),
              have_attributes(test_id: 'aaa', some_int: 3),
              have_attributes(test_id: 'bbb', some_int: 4)
            ]
          )
      end
    end

    describe 'soft deletion' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget
          compacted false

          # Sample customization: Soft delete
          def remove_records(records)
            deleted = deleted_query(records)

            deleted.update_all(
              deleted: true,
              updated_at: Time.zone.now
            )
          end

          # Sample customization: Undelete records
          def record_attributes(payload, key)
            super.merge(deleted: false)
          end
        end
      end

      it 'should mark records deleted' do
        Widget.create!(id: 1, test_id: 'abc', some_int: 2)
        Widget.create!(id: 3, test_id: 'xyz', some_int: 4)
        Widget.create!(id: 4, test_id: 'uvw', some_int: 5, deleted: true)

        travel 1.day

        publish_batch(
          [
            { key: 1,
              payload: nil },
            { key: 1, # Double delete for key 1
              payload: nil },
            { key: 2, # Create 2
              payload: { test_id: 'def', some_int: 3 } },
            { key: 2, # Delete 2
              payload: nil },
            { key: 3, # Update non-deleted
              payload: { test_id: 'ghi', some_int: 4 } },
            { key: 4, # Revive
              payload: { test_id: 'uvw', some_int: 5 } }
          ]
        )

        expect(all_widgets).
          to match_array(
            [
              have_attributes(id: 1, test_id: 'abc', some_int: 2, deleted: true,
                              created_at: start, updated_at: Time.zone.now),
              have_attributes(id: 2, test_id: 'def', some_int: 3, deleted: true,
                              created_at: Time.zone.now, updated_at: Time.zone.now),
              have_attributes(id: 3, test_id: 'ghi', some_int: 4, deleted: false,
                              created_at: start, updated_at: Time.zone.now),
              have_attributes(id: 4, test_id: 'uvw', some_int: 5, deleted: false,
                              created_at: start, updated_at: Time.zone.now)
            ]
          )
      end
    end

    describe 'skipping records' do
      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget

          # Sample customization: Skipping records
          def record_attributes(payload, key)
            return nil if payload[:test_id] == 'skipme'

            super
          end
        end
      end

      it 'should allow overriding to skip any unwanted records' do
        publish_batch(
          [
            { key: 1, # Record that consumer can decide to skip
              payload: { test_id: 'skipme' } },
            { key: 2,
              payload: { test_id: 'abc123' } }
          ]
        )

        expect(all_widgets).
          to match_array([have_attributes(id: 2, test_id: 'abc123')])
      end
    end

    describe 'pre processing' do
      context 'with uncompacted messages' do
        let(:consumer_class) do
          Class.new(described_class) do
            schema 'MySchema'
            namespace 'com.my-namespace'
            key_config plain: true
            record_class Widget
            compacted false

            def pre_process(messages)
              messages.each do |message|
                message.payload[:some_int] = -message.payload[:some_int]
              end
            end

          end
        end

        it 'should pre-process records' do
          Widget.create!(id: 1, test_id: 'abc', some_int: 1)
          Widget.create!(id: 2, test_id: 'def', some_int: 2)

          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'abc', some_int: 11 } },
              { key: 2,
                payload: { test_id: 'def', some_int: 20 } }
            ]
          )

          widget_one, widget_two = Widget.all.to_a

          expect(widget_one.some_int).to eq(-11)
          expect(widget_two.some_int).to eq(-20)
        end
      end
    end

    describe 'global configurations' do

      context 'with a global bulk_import_id_generator' do

        before(:each) do
          Deimos.configure do
            consumers.bulk_import_id_generator(proc { 'global' })
          end
        end

        it 'should call the default bulk_import_id_generator proc' do
          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'abc', some_int: 3 } }
            ]
          )

          expect(all_widgets).
            to match_array(
              [
                have_attributes(id: 1,
                                test_id: 'abc',
                                some_int: 3,
                                updated_at: start,
                                created_at: start,
                                bulk_import_id: 'global')
              ]
            )

        end

      end

      context 'with a class defined bulk_import_id_generator' do

        before(:each) do
          Deimos.configure do
            consumers.bulk_import_id_generator(proc { 'global' })
          end
          consumer_class.config[:bulk_import_id_generator] = proc { 'custom' }
        end

        it 'should call the default bulk_import_id_generator proc' do

          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'abc', some_int: 3 } }
            ]
          )

          expect(all_widgets).
            to match_array(
              [
                have_attributes(id: 1,
                                test_id: 'abc',
                                some_int: 3,
                                updated_at: start,
                                created_at: start,
                                bulk_import_id: 'custom')
              ]
            )

        end
      end

    end

    describe 'should_consume?' do

      let(:consumer_class) do
        Class.new(described_class) do
          schema 'MySchema'
          namespace 'com.my-namespace'
          key_config plain: true
          record_class Widget
          compacted false

          def should_consume?(record)
            record.test_id != 'def'
          end

          def self.process_invalid_records(_)
            nil
          end

          ActiveSupport::Notifications.subscribe('batch_consumption.invalid_records') do |*args|
            payload = ActiveSupport::Notifications::Event.new(*args).payload
            payload[:consumer].process_invalid_records(payload[:records])
          end

        end
      end

      it "should skip records that shouldn't be consumed" do
        Widget.create!(id: 1, test_id: 'abc', some_int: 1)
        Widget.create!(id: 2, test_id: 'def', some_int: 2)
        publish_batch(
          [
            { key: 1,
              payload: { test_id: 'abc', some_int: 11 } },
            { key: 2,
              payload: { test_id: 'def', some_int: 20 } }
          ]
        )

        expect(Widget.count).to eq(2)
        expect(Widget.all.to_a).to match_array([
                                                 have_attributes(id: 1,
                                                                 test_id: 'abc',
                                                                 some_int: 11,
                                                                 updated_at: start,
                                                                 created_at: start),
                                                 have_attributes(id: 2,
                                                                 test_id: 'def',
                                                                 some_int: 2,
                                                                 updated_at: start,
                                                                 created_at: start)
                                               ])
      end

    end

    describe 'post processing' do

      context 'with uncompacted messages' do
        let(:consumer_class) do
          Class.new(described_class) do
            schema 'MySchema'
            namespace 'com.my-namespace'
            key_config plain: true
            record_class Widget
            compacted false

            def should_consume?(record)
              record.some_int.even?
            end

            def self.process_valid_records(valid)
              # Success
              attrs = valid.first.attributes
              Widget.find_by(id: attrs['id'], test_id: attrs['test_id']).update!(some_int: 2000)
            end

            def self.process_invalid_records(invalid)
              # Invalid
              attrs = invalid.first.record.attributes
              Widget.find_by(id: attrs['id'], test_id: attrs['test_id']).update!(some_int: attrs['some_int'])
            end

            ActiveSupport::Notifications.subscribe('batch_consumption.invalid_records') do |*args|
              payload = ActiveSupport::Notifications::Event.new(*args).payload
              payload[:consumer].process_invalid_records(payload[:records])
            end

            ActiveSupport::Notifications.subscribe('batch_consumption.valid_records') do |*args|
              payload = ActiveSupport::Notifications::Event.new(*args).payload
              payload[:consumer].process_valid_records(payload[:records])
            end

          end
        end

        it 'should process successful and failed records' do
          Widget.create!(id: 1, test_id: 'abc', some_int: 1)
          Widget.create!(id: 2, test_id: 'def', some_int: 2)

          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'abc', some_int: 11 } },
              { key: 2,
                payload: { test_id: 'def', some_int: 20 } }
            ]
          )

          widget_one, widget_two = Widget.all.to_a

          expect(widget_one.some_int).to eq(11)
          expect(widget_two.some_int).to eq(2000)
        end
      end

      context 'with compacted messages' do
        let(:consumer_class) do
          Class.new(described_class) do
            schema 'MySchema'
            namespace 'com.my-namespace'
            key_config plain: true
            record_class Widget
            compacted true

            def should_consume?(record)
              record.some_int.even?
            end

            def self.process_valid_records(valid)
              # Success
              attrs = valid.first.attributes
              Widget.find_by(id: attrs['id'], test_id: attrs['test_id']).update!(some_int: 2000)
            end

            def self.process_invalid_records(invalid)
              # Invalid
              attrs = invalid.first.record.attributes
              Widget.find_by(id: attrs['id'], test_id: attrs['test_id']).update!(some_int: attrs['some_int'])
            end

            ActiveSupport::Notifications.subscribe('batch_consumption.invalid_records') do |*args|
              payload = ActiveSupport::Notifications::Event.new(*args).payload
              payload[:consumer].process_invalid_records(payload[:records])
            end

            ActiveSupport::Notifications.subscribe('batch_consumption.valid_records') do |*args|
              payload = ActiveSupport::Notifications::Event.new(*args).payload
              payload[:consumer].process_valid_records(payload[:records])
            end

          end
        end

        it 'should process successful and failed records' do
          Widget.create!(id: 1, test_id: 'abc', some_int: 1)
          Widget.create!(id: 2, test_id: 'def', some_int: 2)

          publish_batch(
            [
              { key: 1,
                payload: { test_id: 'abc', some_int: 11 } },
              { key: 2,
                payload: { test_id: 'def', some_int: 20 } }
            ]
          )

          widget_one, widget_two = Widget.all.to_a

          expect(widget_one.some_int).to eq(11)
          expect(widget_two.some_int).to eq(2000)
        end
      end

      context 'with post processing errors' do
        let(:consumer_class) do
          Class.new(described_class) do
            schema 'MySchema'
            namespace 'com.my-namespace'
            key_config plain: true
            record_class Widget
            compacted false

            def self.process_valid_records(_)
              raise StandardError, 'Something went wrong'
            end

            ActiveSupport::Notifications.subscribe('batch_consumption.valid_records') do |*args|
              payload = ActiveSupport::Notifications::Event.new(*args).payload
              payload[:consumer].process_valid_records(payload[:records])
            end

          end
        end

        it 'should save records if an exception occurs in post processing' do
          Widget.create!(id: 1, test_id: 'abc', some_int: 1)
          Widget.create!(id: 2, test_id: 'def', some_int: 2)

          expect {
            publish_batch(
              [
                { key: 1,
                  payload: { test_id: 'abc', some_int: 11 } },
                { key: 2,
                  payload: { test_id: 'def', some_int: 20 } }
              ]
            )
          }.to raise_error(StandardError, 'Something went wrong')

          widget_one, widget_two = Widget.all.to_a

          expect(widget_one.some_int).to eq(11)
          expect(widget_two.some_int).to eq(20)

        end
      end

    end

  end
end
