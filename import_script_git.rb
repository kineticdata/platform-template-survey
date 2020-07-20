#Updated 2020-06-01 By Brian Peterson

# NOTES
# This is a migration tool not an installation tool.  There are certain expectations that the destination is configured and working.
# Agent Server(s) must be added ahead of migration.  /space/settings/platformComponents/agents
# Task Server must be added ahead of migration.  /space/settings/platformComponents/task
# Task Sources must be manually maintained
# Bridges must be added ahead of migration.  /space/plugins/bridges
# Agent Handlers are not migrated by design.  They intentionally must be manually added.
# Categories on the Kapp are not updated or deleted from the destination server (see TODO below)
# Teams are not deleted from destination.  It could be too dangerous to delete them.

# TODO
# Can the file path be used in the delete processes to help determine what was deleted.
# Incorportate the form_type files into the script.

# RUNNING THE SCRIPT:
#   ruby import_script.rb -c "<<Dir/CONFIG_FILE.rb>>"
#   ruby import_script -c "config/foo-web-server.rb"
#
# Example Config File Values (See Readme for additional details)
#
=begin yml config file example

  ---
  core:
    # server_url: https://<SPACE>.kinops.io  OR https://<SERVER_NAME>.com/kinetic/<SPACE_SLUG>
    server_url: https://web-server.com
    space_slug: <SPACE_SLUG>
    space_name: <SPACE_NAME>
    service_user_username: <USER_NAME>
    service_user_password: <PASSWORD>
  options:
    delete: true
  task:
    # server_url: https://<SPACE>.kinops.io/app/components/task   OR https://<SERVER_NAME>.com/kinetic/kinetic-task
    server_url: https://web-server.com
    service_user_username: <USER_NAME>
    service_user_password: <PASSWORD>
  http_options:
    log_level: info
    log_output: stderr

=end

require 'logger'
require 'json'
require 'rexml/document'
require 'optparse'
require 'kinetic_sdk'
require 'git'
include REXML

template_name = "platform-template"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

#########################################

# Determine the Present Working Directory
pwd = File.expand_path(File.dirname(__FILE__))

ARGV << '-h' if ARGV.empty?

# The options specified on the command line will be collected in *options*.
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("-c", "--c CONFIG_FILE", "The Configuration file to use") do |config|
    options["CONFIG_FILE"] = config
  end

  # No argument, shows at tail.  This will print an options summary.
  # Try it and see!
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

#Now raise an exception if we have not found a CONFIG_FILE option
raise OptionParser::MissingArgument if options["CONFIG_FILE"].nil?


# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")


# determine the directory paths
pwd = File.dirname(File.expand_path(__FILE__))

# setup git
g = Git.open(pwd)
commit_1 = 'HEAD^'
commit_2 = 'HEAD'

# ------------------------------------------------------------------------------
# methods
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# constants
# ------------------------------------------------------------------------------



# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }



# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------
vars = {}
# Read the config file specified in the command line into the variable "vars"
if File.file?(file = "#{platform_template_path}/#{options['CONFIG_FILE']}")
  vars.merge!( YAML.load(File.read("#{platform_template_path}/#{options['CONFIG_FILE']}")) )
elsif
  raise "Config file not found: #{file}"
end

# Set http_options based on values provided in the config file.
http_options = (vars["http_options"] || {}).each_with_object({}) do |(k,v),result|
  result[k.to_sym] = v
end

# Set option values to default values if not included
vars["options"] = !vars["options"].nil? ? vars["options"] : {}
vars["options"]["delete"] = !vars["options"]["delete"].nil? ? vars["options"]["delete"] : false

logger.info "Importing using the config: #{vars}"


space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server_url"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" })
})

puts "Are you sure you want to perform an import of data to #{vars["core"]["server_url"]}? (Y/N)"
case (gets.downcase.chomp)
when 'y'
  puts "Continuing Import"
else
  raise "Exiting Import"
end

###################################################################

# ------------------------------------------------------------------------------
# Update Space Attributes
# ------------------------------------------------------------------------------


file_path = "core/space/spaceAttributeDefinitions.json"

if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceSpaceAttributeArray = []
  destinationSpaceAttributeArray = JSON.parse(space_sdk.find_space_attribute_definitions().content_string)['spaceAttributeDefinitions'].map { |definition|  definition['name']}

  spaceAttributeDefinitions = JSON.parse(file_diff.blob().contents)
  spaceAttributeDefinitions.each { | body |
      if destinationSpaceAttributeArray.include?(body['name'])
        space_sdk.update_space_attribute_definition(body['name'], body)
      else
        space_sdk.add_space_attribute_definition(body['name'], body['description'], body['allowsMultiple'])
      end
      sourceSpaceAttributeArray.push(body['name'])
  }
  destinationSpaceAttributeArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceSpaceAttributeArray.include?(spaceAttribute)
        space_sdk.delete_space_attribute_definition(spaceAttribute)
    end
  }
end

# ------------------------------------------------------------------------------
# Update User Attributes
# ------------------------------------------------------------------------------
file_path = "core/space/userAttributeDefinitions.json"
if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceUserAttributeArray = []
  destinationUserAttributeArray = JSON.parse(space_sdk.find_user_attribute_definitions().content_string)['userAttributeDefinitions'].map { |definition|  definition['name']}

  if File.file?(file = "#{platform_template_path}/#{file_path}")
    userAttributeDefinitions = JSON.parse(file_diff.blob().contents)
    userAttributeDefinitions.each { | body |
        if destinationUserAttributeArray.include?(body['name'])
          space_sdk.update_user_attribute_definition(body['name'], body)
        else
          space_sdk.add_user_attribute_definition(body['name'], body['description'], body['allowsMultiple'])
        end
        sourceUserAttributeArray.push(body['name'])
    }
  end

  destinationUserAttributeArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceUserAttributeArray.include?(spaceAttribute)
        space_sdk.delete_user_attribute_definition(spaceAttribute)
    end
  }
end
# ------------------------------------------------------------------------------
# Update User Profile Attributes
# ------------------------------------------------------------------------------

file_path = "core/space/userProfileAttributeDefinitions.json"
if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceUserProfileAttributeArray = []
  destinationUserProfileAttributeArray = JSON.parse(space_sdk.find_user_profile_attribute_definitions().content_string)['userProfileAttributeDefinitions'].map { |definition|  definition['name']}

  if File.file?(file = "#{platform_template_path}/#{file_path}")
    userProfileAttributeDefinitions = JSON.parse(file_diff.blob().contents)
    userProfileAttributeDefinitions.each { | body |
        if destinationUserProfileAttributeArray.include?(body['name'])
          space_sdk.update_user_profile_attribute_definition(body['name'], body)
        else
          space_sdk.add_user_profile_attribute_definition(body['name'], body['description'], body['allowsMultiple'])
        end
        sourceUserProfileAttributeArray.push(body['name'])
    }
  end

  destinationUserProfileAttributeArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceUserProfileAttributeArray.include?(spaceAttribute)
        space_sdk.delete_user_profile_attribute_definition(spaceAttribute)
    end
  }
end


# ------------------------------------------------------------------------------
# Update Team Attributes
# ------------------------------------------------------------------------------
file_path = "core/space/teamAttributeDefinitions.json"
if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceTeamAttributeArray = []
  destinationTeamAttributeArray = JSON.parse(space_sdk.find_team_attribute_definitions().content_string)['teamAttributeDefinitions'].map { |definition|  definition['name']}

  if File.file?(file = "#{platform_template_path}/#{file_path}")
    teamAttributeDefinitions = JSON.parse(file_diff.blob().contents)
    teamAttributeDefinitions.each { | body |
        if destinationTeamAttributeArray.include?(body['name'])
          space_sdk.update_team_attribute_definition(body['name'], body)
        else
          space_sdk.add_team_attribute_definition(body['name'], body['description'], body['allowsMultiple'])
        end
        sourceTeamAttributeArray.push(body['name'])
    }
  end

  destinationTeamAttributeArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceTeamAttributeArray.include?(spaceAttribute)
        space_sdk.delete_team_attribute_definition(spaceAttribute)
    end
  }
end
# ------------------------------------------------------------------------------
# Update Datastore Attributes
# ------------------------------------------------------------------------------
file_path = "core/space/datastoreFormAttributeDefinitions.json"
if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceDatastoreAttributeArray = []
  destinationDatastoreAttributeArray = JSON.parse(space_sdk.find_datastore_form_attribute_definitions().content_string)['datastoreFormAttributeDefinitions'].map { |definition|  definition['name']}

  if File.file?(file = "#{platform_template_path}/#{file_path}")
    datastoreFormAttributeDefinitions = JSON.parse(file_diff.blob().contents)
    datastoreFormAttributeDefinitions.each { | body |
        if destinationDatastoreAttributeArray.include?(body['name'])
          space_sdk.update_datastore_form_attribute_definition(body['name'], body)
        else
          space_sdk.add_datastore_form_attribute_definition(body['name'], body['description'], body['allowsMultiple'])
        end
        sourceDatastoreAttributeArray.push(body['name'])
    }
  end

  destinationDatastoreAttributeArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceDatastoreAttributeArray.include?(spaceAttribute)
        space_sdk.delete_datastore_form_attribute_definition(spaceAttribute)
    end
  }
end

# ------------------------------------------------------------------------------
# Update Security Policy
# ------------------------------------------------------------------------------
file_path = "core/space/securityPolicyDefinitions.json"
if file_diff = g.diff(commit_1, commit_2).path(file_path).first
  sourceSecurityPolicyArray = []
  destinationSecurityPolicyArray = JSON.parse(space_sdk.find_space_security_policy_definitions().content_string)['securityPolicyDefinitions'].map { |definition|  definition['name']}
  if File.file?(file = "#{platform_template_path}/#{file_path}")
    securityPolicyDefinitions = JSON.parse(file_diff.blob().contents)
    securityPolicyDefinitions.each { | body |
        if destinationSecurityPolicyArray.include?(body['name'])
          space_sdk.update_space_security_policy_definition(body['name'], body)
        else
          space_sdk.add_space_security_policy_definition(body)
        end
        sourceSecurityPolicyArray.push(body['name'])
    }
  end

  destinationSecurityPolicyArray.each { | spaceAttribute |
    if vars["options"]["delete"] && !sourceSecurityPolicyArray.include?(spaceAttribute)
        space_sdk.delete_space_security_policy_definition(spaceAttribute)
    end
  }
end

# ------------------------------------------------------------------------------
# import bridge models
# *NOTE* - This if the bridge doesn't exist the model will be imported w/ an empty "Bridge Slug" value.
# ------------------------------------------------------------------------------
  logger.info "Importing Bridge Models for #{vars["core"]["space_slug"]}"

  destinationModels = space_sdk.find_bridge_models()
  destinationModels_Array = JSON.parse(destinationModels.content_string)['models'].map{ |model| model['activeMappingName']}
  file_path = "core/space/models"
  g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
    type = file_diff.type
    body = JSON.parse(file_diff.blob().contents) unless file_diff.blob().nil?
    file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
    if type=="modified"
      if destinationModels_Array.include?(body['name'])
        space_sdk.update_bridge_model(body['name'], body)
      elsif destinationModels_Array.include?(file_name)
        space_sdk.add_bridge_model(body)
        space_sdk.delete_bridge_model(file_name)
      end
    elsif type=="new"
      space_sdk.add_bridge_model(body)
    elsif type=="deleted" && vars["options"]["delete"] && destinationModels_Array.include?(file_name)
      space_sdk.delete_bridge_model(file_name)
    end
  }

# ------------------------------------------------------------------------------
# import datastore forms
# ------------------------------------------------------------------------------
logger.info "Importing datastore forms for #{vars["core"]["space_slug"]}"

destinationDatastoreForms = [] #From destination server
sourceDatastoreForms = [] #From import data
file_path = "core/space/datastore/forms/\*.json"
datastoreForms = space_sdk.find_datastore_forms()
destinationDatastoreForms = JSON.parse(datastoreForms.content_string)['forms'].map{ |model| model['slug']}

g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
  type = file_diff.type
  body = JSON.parse(file_diff.blob().contents) unless file_diff.blob().nil?
  file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  if type=="modified"
    if destinationDatastoreForms.include?(body['name'])
      space_sdk.update_datastore_form(body['name'], body)
    elsif destinationDatastoreForms.include?(file_name)
      space_sdk.add_datastore_form(body)
      space_sdk.delete_datastore_form(file_name)
    end
  elsif type=="new"
    space_sdk.add_datastore_form(body)
  elsif type=="deleted" && vars["options"]["delete"] && destinationDatastoreForms.include?(file_name)
    space_sdk.delete_datastore_form(file_name)
  end
}



# ------------------------------------------------------------------------------
# Import Datastore Data
# ------------------------------------------------------------------------------
logger.info "Importing datastore submissions for #{vars["core"]["space_slug"]}"
destinationDatastoreFormSubmissions = {}
sourceDatastoreFormSubmissions = {}
file_path = "core/space/datastore/forms/\*/\*.ndjson"

# import kapp & datastore submissions
g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
  puts file_diff.path
  puts pwd
  type = file_diff.type
  # get the form slug from the 2nd to last place in the path of the submission.ndjson file (ie: core\space\datastore\forms\alert\submissions.ndjson)
  puts form_slug = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}[-2]
  Array(space_sdk.find_all_form_datastore_submissions(form_slug).content['submissions']).each { |submission|
    space_sdk.delete_datastore_submission(submission['id'])
  }
  File.readlines("#{pwd}/#{file_diff.path}").each do |line|
    submission = JSON.parse(line)
    body = {
      "values" => submission["values"],
      "coreState" => submission["coreState"]
    }
    space_sdk.add_datastore_submission(form_slug, body).content
  end
}


# ------------------------------------------------------------------------------
# import space teams
# ------------------------------------------------------------------------------
logger.info "Importing Teams for #{vars["core"]["space_slug"]}"
SourceTeamArray = []
file_path = "core/space/teams/\*.json"
destinationTeams = JSON.parse(space_sdk.find_teams().content_string)['teams'].map{ |team| {"slug" => team['slug'], "name"=>team['name']} }
g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
  type = file_diff.type
  body = JSON.parse(file_diff.blob().contents) unless file_diff.blob().nil?
  file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  if type=="modified"
    if destinationTeams.include?(body['name'])
      space_sdk.update_team(body['name'], body)
    elsif destinationTeams.include?(file_name)
      space_sdk.add_team(body)
      #Delete has been disabled.  It is potentially too dangerous to include w/o advanced knowledge.
      #space_sdk.delete_team(team['slug'])
    end
  elsif type=="new"
    space_sdk.add_team(body)
  elsif type=="deleted" && vars["options"]["delete"] && destinationTeams.include?(file_name)
    #Delete has been disabled.  It is potentially too dangerous to include w/o advanced knowledge.
    #space_sdk.delete_team(team['slug'])
  end

  #Add Attributes to the Team
  body['attributes'].each{ | body |
    space_sdk.add_team_attribute(body['name'], body['name'], body['values'])
  }
  SourceTeamArray.push({'name' => body['name'], 'slug'=>body['slug']} )
}

# ------------------------------------------------------------------------------
# import space webhooks
# ------------------------------------------------------------------------------
logger.info "Importing Webhooks for #{vars["core"]["space_slug"]}"

file_path = "space/webhooks/*.json"
sourceSpaceWebhooksArray = []
destinationSpaceWebhooksArray = JSON.parse(space_sdk.find_webhooks_on_space().content_string)['webhooks'].map{ |webhook| webhook['name']}

g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
  type = file_diff.type
  body = JSON.parse(file_diff.blob().contents) unless file_diff.blob().nil?
  file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  if type=="modified"
    if destinationTeams.include?(body['name'])
      space_sdk.update_webhook_on_space(body['name'], body)
    elsif destinationTeams.include?(file_name)
      space_sdk.add_webhook_on_space(body)
      space_sdk.delete_webhook_on_space(webhook)
    end
  elsif type=="new"
    space_sdk.add_webhook_on_space(body)
  elsif type=="deleted" && vars["options"]["delete"] && destinationTeams.include?(file_name)
    space_sdk.delete_webhook_on_space(webhook)
  end
}


# ------------------------------------------------------------------------------
# import kapp data
# ------------------------------------------------------------------------------

Dir["#{core_path}/space/kapps/*.json"].each { |file|
  kapp_slug = file.split('/').last.gsub('.json', '') # extract the kapp slug from the file path

  # if the <kapp_slug>.json is in the diff the kapp was updated
  file_path = file.gsub(pwd+'/','')  # convert file path to git directory
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    kappExists = space_sdk.find_kapp(kapp_slug).code.to_i == 200
    logger.info "Importing Kapp Definitions for #{kapp_slug} Kapp"
    kapp_body= JSON.parse(file_diff.blob().contents) unless file_diff.nil?
    if kappExists
      space_sdk.update_kapp(kapp_body['slug'], kapp_body)
    else
      space_sdk.add_kapp(kapp_body['name'], kapp_body['slug'], kapp_body)
    end
  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Attribute Definitions
  # ------------------------------------------------------------------------------
  logger.info "Importing Kapp Attribute Definitions for #{kapp_slug} Kapp"
  file_path = "core/space/kapps/#{kapp_slug}/kappAttributeDefinitions.json"
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    sourceKappAttributeArray = []
    destinationKappAttributeArray = JSON.parse(space_sdk.find_kapp_attribute_definitions(kapp_slug).content_string)['kappAttributeDefinitions'].map { |definition|  definition['name']}
    kappAttributeDefinitions = JSON.parse(file_diff.blob().contents)
    kappAttributeDefinitions.each { |body|
        if destinationKappAttributeArray.include?(body['name'])
          space_sdk.update_kapp_attribute_definition(kapp_slug, body['name'], body)
        else
          space_sdk.add_kapp_attribute_definition(kapp_slug, body['name'], body['description'], body['allowsMultiple'])
        end
        sourceKappAttributeArray.push(body['name'])
    }

    destinationKappAttributeArray.each { | body |
      if vars["options"]["delete"] && !sourceKappAttributeArray.include?(body)
          space_sdk.delete_kapp_attribute_definition(kapp_slug,body)
      end
    }
  end
  # ------------------------------------------------------------------------------
  # Migrate Kapp Category Definitions
  # ------------------------------------------------------------------------------
  logger.info "Importing Kapp Attribute Definitions for #{kapp_slug} Kapp"
  file_path = "core/space/kapps/#{kapp_slug}/categoryAttributeDefinitions.json"
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    sourceKappCategoryArray = []
    destinationKappAttributeArray = JSON.parse(space_sdk.find_category_attribute_definitions(kapp_slug).content_string)['categoryAttributeDefinitions'].map { |definition|  definition['name']}
      kappCategoryDefinitions = JSON.parse(file_diff.blob().contents)

      kappCategoryDefinitions.each { | body |
          if destinationKappAttributeArray.include?(body['name'])
            space_sdk.update_category_attribute_definition(kapp_slug, body['name'], body)
          else
            space_sdk.add_category_attribute_definition(kapp_slug, body['name'], body['description'], body['allowsMultiple'])
          end
          sourceKappCategoryArray.push(body['name'])
      }
    destinationKappAttributeArray.each { | body |
      if !sourceKappCategoryArray.include?(body)
          space_sdk.delete_category_attribute_definition(kapp_slug,body)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Form Attribute Definitions
  # ------------------------------------------------------------------------------
  logger.info "Importing Form Attribute Definitions for #{kapp_slug} Kapp"
  file_path = "core/space/kapps/#{kapp_slug}/categoryAttributeDefinitions.json"
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    sourceFormAttributeArray = []
    destinationFormAttributeArray = JSON.parse(space_sdk.find_form_attribute_definitions(kapp_slug).content_string)['formAttributeDefinitions'].map { |definition|  definition['name']}
    formAttributeDefinitions = JSON.parse(file_diff.blob().contents)

    formAttributeDefinitions.each { | body |
        if destinationFormAttributeArray.include?(body['name'])
          space_sdk.update_form_attribute_definition(kapp_slug, body['name'], body)
        else
          space_sdk.add_form_attribute_definition(kapp_slug, body['name'], body['description'], body['allowsMultiple'])
        end
        sourceFormAttributeArray.push(body['name'])
    }

    destinationFormAttributeArray.each { | body |
      if vars["options"]["delete"] && !sourceFormAttributeArray.include?(body)
          space_sdk.delete_form_attribute_definition(kapp_slug,body)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Security Policy Definitions
  # ------------------------------------------------------------------------------
  logger.info "Importing Form Attribute Definitions for #{kapp_slug} Kapp"
  file_path = "core/space/kapps/#{kapp_slug}/securityPolicyDefinitions.json"
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    sourceSecurtyPolicyArray = []
    destinationSecurtyPolicyArray = JSON.parse(space_sdk.find_security_policy_definitions(kapp_slug).content_string)['securityPolicyDefinitions'].map { |definition|  definition['name']}
    securityPolicyDefinitions = JSON.parse(file_diff.blob().contents)

    securityPolicyDefinitions.each { | body |
        if destinationSecurtyPolicyArray.include?(body['name'])
          space_sdk.update_security_policy_definition(kapp_slug, body['name'], body)
        else
          space_sdk.add_security_policy_definition(kapp_slug, body)
        end
        sourceSecurtyPolicyArray.push(body['name'])
    }

    destinationSecurtyPolicyArray.each { | body |
      if vars["options"]["delete"] && !sourceSecurtyPolicyArray.include?(body)
          space_sdk.delete_security_policy_definition(kapp_slug,body)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Categories on the Kapp
  # ------------------------------------------------------------------------------
  logger.info "Importing Form Categories for #{kapp_slug} Kapp"
  file_path = "core/space/kapps/#{kapp_slug}/categories.json"
  if file_diff = g.diff(commit_1, commit_2).path(file_path).first
    sourceCategoryArray = []
    destinationCategoryArray = JSON.parse(space_sdk.find_categories(kapp_slug).content_string)['categories'].map { |definition|  definition['name']}
    categories = JSON.parse(file_diff.blob().contents)
    categories.each { | body |
      if destinationCategoryArray.include?(body['name'])
        space_sdk.update_category_on_kapp(kapp_slug, body['slug'], body)
      else
        space_sdk.add_category_on_kapp(kapp_slug, body)
      end
      sourceCategoryArray.push(body['name'])
    }

    # ------------------------------------------------------------------------------
    # Delete Categories on the Kapp
    # ------------------------------------------------------------------------------

    destinationCategoryArray.each { | body |
      if !sourceCategoryArray.include?(body)
          space_sdk.delete_category_on_kapp(kapp_slug,body)
      end
    }
  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Webhooks
  # ------------------------------------------------------------------------------
  logger.info "Importing Webhooks for #{kapp_slug} Kapp"

  file_path = "core/space/kapps/#{kapp_slug}/webhooks/*.json"
  sourceWebhookArray = []
  destinationWebhookArray = JSON.parse(space_sdk.find_webhooks_on_kapp(kapp_slug).content_string)['webhooks'].map { |definition|  definition['name']}
  g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|

    body = JSON.parse(file_diff.blob().contents)
    if destinationWebhookArray.include?(body['name'])
      space_sdk.update_webhook_on_kapp(kapp_slug, body['name'], body)
    else
      space_sdk.add_webhook_on_kapp(kapp_slug, body)
    end
    sourceWebhookArray.push(body['name'])

    # ------------------------------------------------------------------------------
    # delete Kapp Webhooks
    # ------------------------------------------------------------------------------
    destinationWebhookArray.each { | body |
      if vars["options"]["delete"] && !sourceWebhookArray.include?(body)
          space_sdk.delete_webhook_on_kapp(kapp_slug,body)
      end
    }
  }

  # ------------------------------------------------------------------------------
  # add forms
  # ------------------------------------------------------------------------------
  logger.info "Importing Forms for #{kapp_slug} Kapp"

  file_path = "core/space/kapps/#{kapp_slug}/forms/*.json"
  sourceForms = []
  destinationForms = JSON.parse(space_sdk.find_forms(kapp_slug).content_string)['forms'].map{ |form| form['slug']}
  g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
    type = file_diff.type
    body = JSON.parse(file_diff.blob().contents)
    file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
    if type=="modified"
      if destinationForms.include?(body['slug'])
        space_sdk.update_form(kapp_slug ,body['slug'], file_diff)
      elsif destinationForms.include?(file_name)
        space_sdk.add_form(kapp_slug, body)
        space_sdk.delete_form(kapp_slug, body['slug'])
      end
    elsif type=="new"
      space_sdk.add_form(kapp_slug, body)
    elsif type=="deleted" && vars["options"]["delete"] && destinationTeams.include?(file_name)
      space_sdk.delete_form(kapp_slug, body['slug'])
    end
  }

  # ------------------------------------------------------------------------------
  # End of Kapp Import Loop
  # ------------------------------------------------------------------------------

}

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["task"]["server_url"]}",
  username: vars["task"]["service_user_username"],
  password: vars["task"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" })
})

# ------------------------------------------------------------------------------
# task import
# ------------------------------------------------------------------------------

logger.info "Importing the task components for the \"#{template_name}\" template."
logger.info "  importing with api: #{task_sdk.api_url}"

# ------------------------------------------------------------------------------
# task handlers
# ------------------------------------------------------------------------------

# import handlers forcing overwrite
#task_sdk.import_handlers(true)



logger.info "Importing the Sources the for #{vars["core"]["space_slug"]}"

puts file_path = "task/sources/*.json"
g.diff(commit_1, commit_2).path(file_path).each { | file_diff |
  puts type = file_diff.type

  puts file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  if !file_diff.blob().nil?
    puts body = JSON.parse(file_diff.blob().contents)
    source =body.select { |k,v| k == "name" }
  end
  if type == "new"
    puts body.class
    puts body.inspect
    task_sdk.add_source({
  "name": "Kinetic Request CE",
  "status": "Active",
  "type": "Kinetic Request CE",
  "properties": {
    "Proxy Username": "integration-user",
    "Web Server": "https://3724281.kinops.io",
    "Space Slug": ""
  }
})
  elsif type == "modified"
    task_sdk.update_source(source,body)
  elsif type == "deleted"
    source_contents = ""
    # match lines betweeen -{ and -} which identifies the prior file contents
    file_diff.patch.match(/-{([\S\s]*?)-}/).to_s.each_line do |line|
      source_contents += line.gsub(/^-{1}/,'')
    end
    source_name = JSON.parse(source_contents)['name']
    task_sdk.delete_source(source_name)
  end
}

# ------------------------------------------------------------------------------
# Import Task Trees and Routines
# ------------------------------------------------------------------------------

Dir["#{task_path}/sources/*.json"].each {|source|
  body = JSON.parse(File.read(source))
  source_file_name = source.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.json','')
  source_name = body['name']



  logger.info "Importing Trees in #{source_name} source the for #{vars["core"]["space_slug"]}"
  file_path = "#{task_path}/sources/#{source_file_name}/*.xml"
  g.diff(commit_1, commit_2).path(file_path).each{ |file_diff|
    type = file_diff.type
    file_name = file_diff.path.split(File::SEPARATOR).map {|x| x=="" ? File::SEPARATOR : x}.last.gsub('.xml','')
    if type=="modified" || type=="new"
      file_path = "#{pwd}/#{file_diff.path}"
      tree_file = File.new(file_path, "rb")
      task_sdk.import_tree(tree_file, true)
    elsif type=="deleted"
      delete_tree = {
             "source_name" => source_name,
             "group_name" =>  file_name.split('.').first.gsub('---', ' > ').capitalize(),
             "tree_name" => file_name.split('.').last.capitalize()
           }
      task_sdk.delete_tree(delete_tree)
    end

  }

}
##########################################
raise "end"
#########################################
# ------------------------------------------------------------------------------
# import task categories
# ------------------------------------------------------------------------------

sourceCategories = [] #From import data
destinationCategories = JSON.parse(task_sdk.find_categories().content_string)['categories'].map{ |category| category['name']}

Dir["#{task_path}/categories/*.json"].each { |file|
  category = JSON.parse(File.read(file))
  sourceCategories.push(category['name'])
  if destinationCategories.include?(category['name'])
    task_sdk.update_category(category['name'], category)
  else
    task_sdk.add_category(category)
  end
}

# ------------------------------------------------------------------------------
# delete task categories
# ------------------------------------------------------------------------------

destinationCategories.each { |category|
  if vars["options"]["delete"] && !sourceCategories.include?(category)
    task_sdk.delete_category(category)
  end
}

# ------------------------------------------------------------------------------
# import task policy rules
# ------------------------------------------------------------------------------

destinationPolicyRuleArray = JSON.parse(task_sdk.find_policy_rules().content_string)['policyRules']
sourcePolicyRuleArray = Dir["#{task_path}/policyRules/*.json"].map{ |file|
    rule = JSON.parse(File.read(file))
    {"name" => rule['name'], "type" => rule['type']}
  }

Dir["#{task_path}/policyRules/*.json"].each { |file|
  rule = JSON.parse(File.read(file))
  if !destinationPolicyRuleArray.find {|dest_rule| dest_rule['name']==rule['name'] && dest_rule['type']==rule['type'] }.nil?
    task_sdk.update_policy_rule(rule.slice('type', 'name'), rule)
  else
    task_sdk.add_policy_rule(rule)
  end
}

# ------------------------------------------------------------------------------
# delete task policy rules
# ------------------------------------------------------------------------------
destinationPolicyRuleArray.each { |rule|
  if vars["options"]["delete"] && sourcePolicyRuleArray.find {|source_rule| source_rule['name']==rule['name'] && source_rule['type']==rule['type'] }.nil?
    task_sdk.delete_policy_rule(rule)
  end
}

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished importing the \"#{template_name}\" forms."
