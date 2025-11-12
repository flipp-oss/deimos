# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::BatchConsumption do
  let(:batch_consumer) do
    Deimos::ActiveRecordConsumer.new
  end

  describe '#update_database' do
    describe 'upsert_records' do
      let(:records) do
        [
          Deimos::Message.new({ v: 1 }, key: 1),
          Deimos::Message.new({ v: 2 }, key: 2),
          Deimos::Message.new({ v: 3 }, key: 3),
          Deimos::Message.new({ v: 4 }, key: 4),
          Deimos::Message.new({ v: 5 }, key: 5)
        ]
      end

      it 'should be called 1 time when record size < max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size + 1
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record size == max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record size > max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size - 1
        expect(batch_consumer).to receive(:upsert_records).twice

        batch_consumer.send(:update_database, records)
      end

      it 'should be called records.size times when max batch size is 1' do
        batch_consumer.class.config[:max_db_batch_size] = 1
        expect(batch_consumer).to receive(:upsert_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.class.config[:max_db_batch_size] = nil
        expect(batch_consumer).to receive(:upsert_records).once

        batch_consumer.send(:update_database, records)
      end
    end

    describe 'remove_records' do
      let(:records) do
        [
          Deimos::Message.new(nil, key: 1),
          Deimos::Message.new(nil, key: 2),
          Deimos::Message.new(nil, key: 3),
          Deimos::Message.new(nil, key: 4),
          Deimos::Message.new(nil, key: 5)
        ]
      end

      it 'should be called 1 time when record size < max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size + 1
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record size == max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record size > max batch size' do
        batch_consumer.class.config[:max_db_batch_size] = records.size - 1
        expect(batch_consumer).to receive(:remove_records).twice

        batch_consumer.send(:update_database, records)
      end

      it 'should be called record.size times when max batch size is 1' do
        batch_consumer.class.config[:max_db_batch_size] = 1
        expect(batch_consumer).to receive(:remove_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.class.config[:max_db_batch_size] = nil
        expect(batch_consumer).to receive(:remove_records).once

        batch_consumer.send(:update_database, records)
      end
    end
  end

  describe '#compact_messages' do
    it 'for scalars' do
      message1 = Deimos::Message.new({ v: 'first' }, key: 1234)
      message2 = Deimos::Message.new({ v: 'last' }, key: 1234)
      result = batch_consumer.send(:compact_messages, [message1, message2])
      expect(result.size).to eq(1)
      expect(result.first.equal?(message2)).to be(true)
    end

    it 'for hashes' do
      message1 = Deimos::Message.new({ v: 'first' }, key: { a: 1, b: 2.0, c: 'c' })
      message2 = Deimos::Message.new({ v: 'last' }, key: { a: 1, b: 2.0, c: 'c' })
      result = batch_consumer.send(:compact_messages, [message1, message2])
      expect(result.size).to eq(1)
      expect(result.first.equal?(message2)).to be(true)
    end

    it 'for schema classes' do
      klass = Class.new(Deimos::SchemaClass::Record) do
        attr_accessor :some_name

        # @override
        def initialize(some_name: '')
          super
          self.some_name = some_name
        end

        # @override
        def as_json(_opts={})
          {
            'some_name' => @some_name
          }
        end
      end
      stub_const('Schemas::Key', klass)

      message1 = Deimos::Message.new({ v: 'first' }, key: Schemas::Key.new(some_name: '2'))
      message2 = Deimos::Message.new({ v: 'last' }, key: Schemas::Key.new(some_name: '2'))

      result = batch_consumer.send(:compact_messages, [message1, message2])
      expect(result.size).to eq(1)
      expect(result.first.equal?(message2)).to be(true) # The object is same as the latest one in the batch
    end
  end
end
