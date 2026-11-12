Dir.glob(File.join(__dir__, '*_test.rb')).sort.each { |path| require path }
