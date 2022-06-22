# frozen_string_literal: true

require 'activerecord-import'

# Wrap in a module so our classes don't leak out afterwards
# rubocop:disable Metrics/ModuleLength
module KafkaSourceSpec
  RSpec.describe Deimos::KafkaSource do
    before(:all) do
      ActiveRecord::Base.connection.create_table(:widgets, force: true) do |t|
        t.integer(:widget_id)
        t.string(:description)
        t.string(:model_id, default: '')
        t.string(:name)
        t.timestamps
      end
      ActiveRecord::Base.connection.add_index(:widgets, :widget_id)

      # Dummy producer which mimicks the behavior of a real producer
      class WidgetProducer < Deimos::ActiveRecordProducer
        topic 'my-topic'
        namespace 'com.my-namespace'
        schema 'Widget'
        key_config field: :id
      end

      # Dummy producer which mimicks the behavior of a real producer
      class WidgetProducerTheSecond < Deimos::ActiveRecordProducer
        topic 'my-topic-the-second'
        namespace 'com.my-namespace'
        schema 'WidgetTheSecond'
        key_config field: :id
      end

      # Dummy class we can include the mixin in. Has a backing table created
      # earlier.
      class Widget < ActiveRecord::Base
        include Deimos::KafkaSource

        # :nodoc:
        def self.kafka_producers
          [WidgetProducer, WidgetProducerTheSecond]
        end
      end
      Widget.reset_column_information

    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:widgets)
    end

    before(:each) do
      Widget.delete_all
    end

    it 'should send events on creation, update, and deletion' do
      widget = Widget.create!(widget_id: 1, name: 'widget')
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'widget',
                                        id: widget.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, 1)
      expect('my-topic-the-second').to have_sent({
                                                   widget_id: 1,
                                                   model_id: '',
                                                   id: widget.id,
                                                   created_at: anything,
                                                   updated_at: anything
                                                 }, 1)
      widget.update_attribute(:name, 'widget 2')
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'widget 2',
                                        id: widget.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, 1)
      expect('my-topic-the-second').to have_sent({
                                                   widget_id: 1,
                                                   model_id: '',
                                                   id: widget.id,
                                                   created_at: anything,
                                                   updated_at: anything
                                                 }, 1)
      widget.destroy
      expect('my-topic').to have_sent(nil, 1)
      expect('my-topic-the-second').to have_sent(nil, 1)
    end

    it 'should not call generate_payload but still publish a nil payload for deletion' do
      widget = Widget.create!(widget_id: '808', name: 'delete_me!')
      expect(Deimos::ActiveRecordProducer).not_to receive(:generate_payload)
      widget.destroy
      expect('my-topic').to have_sent(nil, widget.id)
      expect('my-topic-the-second').to have_sent(nil, widget.id)
    end

    it 'should send events on import' do
      widgets = (1..3).map do |i|
        Widget.new(widget_id: i, name: "Widget #{i}")
      end
      Widget.import(widgets)
      widgets = Widget.all
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'Widget 1',
                                        id: widgets[0].id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widgets[0].id)
      expect('my-topic').to have_sent({
                                        widget_id: 2,
                                        name: 'Widget 2',
                                        id: widgets[1].id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widgets[1].id)
      expect('my-topic').to have_sent({
                                        widget_id: 3,
                                        name: 'Widget 3',
                                        id: widgets[2].id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widgets[2].id)
    end

    it 'should send events on import with on_duplicate_key_update and existing records' do
      widget1 = Widget.create(widget_id: 1, name: 'Widget 1')
      widget2 = Widget.create(widget_id: 2, name: 'Widget 2')
      widget1.name = 'New Widget 1'
      widget2.name = 'New Widget 2'
      Widget.import([widget1, widget2], on_duplicate_key_update: %i(widget_id name))

      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'New Widget 1',
                                        id: widget1.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widget1.id)
      expect('my-topic').to have_sent({
                                        widget_id: 2,
                                        name: 'New Widget 2',
                                        id: widget2.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widget2.id)
    end

    it 'should not fail when mixing existing and new records for import :on_duplicate_key_update' do
      widget1 = Widget.create(widget_id: 1, name: 'Widget 1')
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'Widget 1',
                                        id: widget1.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widget1.id)

      widget2 = Widget.new(widget_id: 2, name: 'Widget 2')
      widget1.name = 'New Widget 1'
      Widget.import([widget1, widget2], on_duplicate_key_update: %i(widget_id))
      widgets = Widget.all
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: 'New Widget 1',
                                        id: widgets[0].id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widgets[0].id)
      expect('my-topic').to have_sent({
                                        widget_id: 2,
                                        name: 'Widget 2',
                                        id: widgets[1].id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widgets[1].id)
    end

    it 'should send events even if the save fails' do
      widget = Widget.create!(widget_id: 1, name: 'widget')
      expect('my-topic').to have_sent({
                                        widget_id: 1,
                                        name: widget.name,
                                        id: widget.id,
                                        created_at: anything,
                                        updated_at: anything
                                      }, widget.id)
      clear_kafka_messages!
      Widget.transaction do
        widget.update_attribute(:name, 'widget 3')
        raise ActiveRecord::Rollback
      end
      expect('my-topic').to have_sent(anything)
    end

    it 'should not send events if an unrelated field changes' do
      widget = Widget.create!(widget_id: 1, name: 'widget')
      clear_kafka_messages!
      widget.update_attribute(:description, 'some description')
      expect('my-topic').not_to have_sent(anything)
    end

    context 'with DB backend' do
      before(:each) do
        Deimos.configure do |config|
          config.producers.backend = :db
        end
        setup_db(DB_OPTIONS.last) # sqlite
        allow(Deimos::Producer).to receive(:produce_batch).and_call_original
      end

      it 'should save to the DB' do
        Widget.create!(widget_id: 1, name: 'widget')
        expect(Deimos::KafkaMessage.count).to eq(2) # 2 producers
      end

      it 'should not save with a rollback' do
        Widget.transaction do
          Widget.create!(widget_id: 1, name: 'widget')
          raise ActiveRecord::Rollback
        end
        expect(Deimos::KafkaMessage.count).to eq(0)
      end
    end

    context 'with import hooks disabled' do
      before(:each) do
        # Dummy class we can include the mixin in. Has a backing table created
        # earlier and has the import hook disabled
        class WidgetNoImportHook < ActiveRecord::Base
          include Deimos::KafkaSource
          self.table_name = 'widgets'

          # :nodoc:
          def self.kafka_config
            {
              update: true,
              delete: true,
              import: false,
              create: true
            }
          end

          # :nodoc:
          def self.kafka_producers
            [WidgetProducer]
          end
        end
        WidgetNoImportHook.reset_column_information
      end

      it 'should not fail when bulk-importing with existing records' do
        widget1 = WidgetNoImportHook.create(widget_id: 1, name: 'Widget 1')
        widget2 = WidgetNoImportHook.create(widget_id: 2, name: 'Widget 2')
        widget1.name = 'New Widget No Import Hook 1'
        widget2.name = 'New Widget No Import Hook 2'

        expect {
          WidgetNoImportHook.import([widget1, widget2], on_duplicate_key_update: %i(widget_id name))
        }.not_to raise_error

        expect('my-topic').not_to have_sent({
                                              widget_id: 1,
                                              name: 'New Widget No Import Hook 1',
                                              id: widget1.id,
                                              created_at: anything,
                                              updated_at: anything
                                            }, widget1.id)
        expect('my-topic').not_to have_sent({
                                              widget_id: 2,
                                              name: 'New Widget No Import Hook 2',
                                              id: widget2.id,
                                              created_at: anything,
                                              updated_at: anything
                                            }, widget2.id)
      end

      it 'should not fail when mixing existing and new records' do
        widget1 = WidgetNoImportHook.create(widget_id: 1, name: 'Widget 1')
        expect('my-topic').to have_sent({
                                          widget_id: 1,
                                          name: 'Widget 1',
                                          id: widget1.id,
                                          created_at: anything,
                                          updated_at: anything
                                        }, widget1.id)

        widget2 = WidgetNoImportHook.new(widget_id: 2, name: 'Widget 2')
        widget1.name = 'New Widget 1'
        WidgetNoImportHook.import([widget1, widget2], on_duplicate_key_update: %i(widget_id))
        widgets = WidgetNoImportHook.all
        expect('my-topic').not_to have_sent({
                                              widget_id: 1,
                                              name: 'New Widget 1',
                                              id: widgets[0].id,
                                              created_at: anything,
                                              updated_at: anything
                                            }, widgets[0].id)
        expect('my-topic').not_to have_sent({
                                              widget_id: 2,
                                              name: 'Widget 2',
                                              id: widgets[1].id,
                                              created_at: anything,
                                              updated_at: anything
                                            }, widgets[1].id)
      end
    end

    context 'with AR models that implement the kafka_producer interface' do
      before(:each) do
        # Dummy class we can include the mixin in. Has a backing table created
        # earlier and has the import hook disabled
        deprecated_class = Class.new(ActiveRecord::Base) do
          include Deimos::KafkaSource
          self.table_name = 'widgets'

          # :nodoc:
          def self.kafka_config
            {
              update: true,
              delete: true,
              import: false,
              create: true
            }
          end

          # :nodoc:
          def self.kafka_producer
            WidgetProducer
          end
        end
        stub_const('WidgetDeprecated', deprecated_class)
        WidgetDeprecated.reset_column_information
      end

      it 'logs a warning and sends the message as usual' do
        expect(Deimos.config.logger).to receive(:warn).with({ message: WidgetDeprecated::DEPRECATION_WARNING })
        widget = WidgetDeprecated.create(widget_id: 1, name: 'Widget 1')
        expect('my-topic').to have_sent({
                                          widget_id: 1,
                                          name: 'Widget 1',
                                          id: widget.id,
                                          created_at: anything,
                                          updated_at: anything
                                        }, widget.id)
      end
    end

    context 'with AR models that do not implement any producer interface' do
      before(:each) do
        # Dummy class we can include the mixin in. Has a backing table created
        # earlier and has the import hook disabled
        buggy_class = Class.new(ActiveRecord::Base) do
          include Deimos::KafkaSource
          self.table_name = 'widgets'

          # :nodoc:
          def self.kafka_config
            {
              update: true,
              delete: true,
              import: false,
              create: true
            }
          end
        end
        stub_const('WidgetBuggy', buggy_class)
        WidgetBuggy.reset_column_information
      end

      it 'raises a NotImplementedError exception' do
        expect {
          WidgetBuggy.create(widget_id: 1, name: 'Widget 1')
        }.to raise_error(NotImplementedError)
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
