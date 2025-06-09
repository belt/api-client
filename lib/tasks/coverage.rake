namespace :coverage do
  desc "Run specs with native Coverage (line/branch/method)"
  task :run do
    ENV["COVERAGE"] = "1"
    Rake::Task[:spec].invoke
  end

  desc "Run mutation testing on changed code (since main)"
  task :mutant do
    puts "NOTE: Mutant Ruby 4.0 support pending parser gem updates"
    sh "ore exec mutant run --use rspec --since main -- 'ApiClient*'"
  end

  desc "Run full mutation testing (slow, Ruby 4.0 limited)"
  task :mutant_full do
    puts "NOTE: Mutant Ruby 4.0 support pending parser gem updates"
    sh "ore exec mutant run --use rspec -- 'ApiClient*'"
  end
end
