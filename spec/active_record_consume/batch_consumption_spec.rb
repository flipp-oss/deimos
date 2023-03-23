# frozen_string_literal: true

RSpec.describe Deimos::ActiveRecordConsume::BatchConsumption do
  let(:batch_consumer) do
    Class.new do
      extend Deimos::ActiveRecordConsume::BatchConsumption
    end
  end

  describe '#update_database' do
    describe 'upsert_records' do
      let(:records) do
        [
          Deimos::Message.new({ v: 1 }, nil, key: 1),
          Deimos::Message.new({ v: 2 }, nil, key: 2),
          Deimos::Message.new({ v: 3 }, nil, key: 3),
          Deimos::Message.new({ v: 4 }, nil, key: 4),
          Deimos::Message.new({ v: 5 }, nil, key: 5)
        ]
      end

      it 'should be called 1 time when record count < max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.count + 1)
        expect(batch_consumer).to receive(:upsert_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record count == max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.count)
        expect(batch_consumer).to receive(:upsert_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record count > max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.size - 1)
        expect(batch_consumer).to receive(:upsert_records).exactly(2)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called records.count times when max batch size is 1' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, 1)
        expect(batch_consumer).to receive(:upsert_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, nil)
        expect(batch_consumer).to receive(:upsert_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end
    end

    describe 'remove_records' do
      let(:records) do
        [
          Deimos::Message.new(nil, nil, key: 1),
          Deimos::Message.new(nil, nil, key: 2),
          Deimos::Message.new(nil, nil, key: 3),
          Deimos::Message.new(nil, nil, key: 4),
          Deimos::Message.new(nil, nil, key: 5)
        ]
      end

      it 'should be called 1 time when record count < max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.count + 1)
        expect(batch_consumer).to receive(:remove_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when record count == max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.count)
        expect(batch_consumer).to receive(:remove_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called multiple times when record count > max batch size' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, records.size - 1)
        expect(batch_consumer).to receive(:remove_records).exactly(2)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called record.count times when max batch size is 1' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, 1)
        expect(batch_consumer).to receive(:remove_records).exactly(records.size)

        batch_consumer.send(:update_database, records)
      end

      it 'should be called 1 time when batch size is nil' do
        batch_consumer.instance_variable_set(:@max_db_batch_size, nil)
        expect(batch_consumer).to receive(:remove_records).exactly(1)

        batch_consumer.send(:update_database, records)
      end
    end
  end
end
