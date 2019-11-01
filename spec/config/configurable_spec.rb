class MyConfig
  include Deimos::Configurable

  configure do
    setting :set1
    setting :set2, 'hi mom'
    setting :group do
      setting :set3, proc { false }
    end

    setting_object :listy do
      setting :list1, 10
      setting :list2, 5
    end
  end
end

describe Deimos::Configurable do
  it 'should configure correctly with default values' do
    expect(MyConfig.config.set1).to be_nil
    expect(MyConfig.config.set2).to eq('hi mom')
    expect(MyConfig.config.group.set3.call).to eq(false)
    expect(MyConfig.config.listy_objects).to be_empty
    expect { MyConfig.config.blah }.to raise_error(NameError)
    expect { MyConfig.config.group.set4 }.to raise_error(NameError)
  end

  it 'should add values' do
    MyConfig.configure do |config|
      config.set1 = 5 # config.x syntax
      set2 nil # method_missing syntax
      config.group.set3 = proc { true }
    end

    # second configure should not blow anything away
    MyConfig.configure do
      listy do
        list1 0
        list2 1
      end
      listy do
        list1 100
        list2 200
      end
    end

    expect(MyConfig.config.set1).to eq(5)
    expect(MyConfig.config.set2).to be_nil
    expect(MyConfig.config.group.set3.call).to eq(true)
    expect(MyConfig.config.listy_objects.map(&:to_h)).
      to eq([
              { list1: 0, list2: 1 },
              { list1: 100, list2: 200 }
            ])

    # test reset!
    MyConfig.config.reset!
    expect(MyConfig.config.set1).to be_nil
    expect(MyConfig.config.set2).to eq('hi mom')
    expect(MyConfig.config.group.set3.call).to eq(false)
    expect(MyConfig.config.listy_objects).to be_empty
  end

  it 'should add with block syntax' do
    MyConfig.configure do
      group do
        set3 proc { true }
      end
    end
    expect(MyConfig.config.group.set3.call).to eq(true)
  end

end
