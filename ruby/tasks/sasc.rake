namespace :sasc do
  desc "Regenerate the OpenApi JSON file"
  task gen_openapi: :environment do
    version = SASC::Versioning.latest_version.to_s
    current_ver_path = "openapi/current.json"
    named_ver_path = "openapi/v#{version}.json.gz"

    old_json = File.read(current_ver_path)
    json = SASC::OpenApiGenerator.new("Swell Investing API", Rails.application.routes).generate
    if json == old_json
      TaskLogger.log_and_print "OpenAPI is unchanged"
      next
    end

    File.write(current_ver_path, json)
    gzipped_json = ActiveSupport::Gzip.compress(json)
    File.binwrite(named_ver_path, gzipped_json)
    TaskLogger.log_and_print "Wrote OpenAPI to #{current_ver_path} and #{named_ver_path}"

    changelog_path = "openapi/changelog.json.gz"
    changelog_json = JSON.pretty_generate(SASC::VersionChangelog.build)
    gzipped_changelog_json = ActiveSupport::Gzip.compress(changelog_json)
    File.binwrite(changelog_path, gzipped_changelog_json)
    TaskLogger.log_and_print "Wrote changelog to #{changelog_path}"
  end

  desc "Fail if the OpenAPI in the repo is not up-to-date"
  task assert_openapi_unchanged: :environment do
    original_path = "openapi/current.json"
    repo_api = JSON.parse File.read(original_path)
    cur_api = JSON.parse SASC::OpenApiGenerator.new("Swell Investing API", Rails.application.routes).generate
    diff = SASC::Versioning::Diff.new(repo_api, cur_api, expand: false)

    if diff.empty?
      TaskLogger.log_and_print "API matches #{original_path}"
    else
      TaskLogger.log_and_print "API differs from #{original_path}!"
      puts diff.to_s
      puts
      if diff.trivial?
        puts "All changes are trivial, you probably just need to regenerate the file:"
        puts
        puts " $ bundle exec rake sasc:gen_openapi"
      else
        puts "***********************************************************************************"
        puts "*** You probably need to make a new version. See docs/APIVersioning.md details. ***"
        puts "***********************************************************************************"
      end
      puts

      exit 1
    end
  end
end
