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

sourceSpaceAttributeArray = []
destinationSpaceAttributeArray = JSON.parse(space_sdk.find_space_attribute_definitions().content_string)['spaceAttributeDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/spaceAttributeDefinitions.json")
  spaceAttributeDefinitions = JSON.parse(File.read(file))

  spaceAttributeDefinitions.each { |attribute|
      if destinationSpaceAttributeArray.include?(attribute['name'])
        space_sdk.update_space_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_space_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceSpaceAttributeArray.push(attribute['name'])
  }  
end   

destinationSpaceAttributeArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceSpaceAttributeArray.include?(spaceAttribute)
      space_sdk.delete_space_attribute_definition(spaceAttribute)
  end
}

# ------------------------------------------------------------------------------
# Update User Attributes
# ------------------------------------------------------------------------------
sourceUserAttributeArray = []
destinationUserAttributeArray = JSON.parse(space_sdk.find_user_attribute_definitions().content_string)['userAttributeDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/userAttributeDefinitions.json")
  userAttributeDefinitions = JSON.parse(File.read(file))
  userAttributeDefinitions.each { |attribute|
      if destinationUserAttributeArray.include?(attribute['name'])
        space_sdk.update_user_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_user_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceUserAttributeArray.push(attribute['name'])
  }  
end

destinationUserAttributeArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceUserAttributeArray.include?(spaceAttribute)
      space_sdk.delete_user_attribute_definition(spaceAttribute)
  end
}
# ------------------------------------------------------------------------------
# Update User Profile Attributes
# ------------------------------------------------------------------------------

sourceUserProfileAttributeArray = []
destinationUserProfileAttributeArray = JSON.parse(space_sdk.find_user_profile_attribute_definitions().content_string)['userProfileAttributeDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/userProfileAttributeDefinitions.json")
  userProfileAttributeDefinitions = JSON.parse(File.read(file))

  userProfileAttributeDefinitions.each { |attribute|
      if destinationUserProfileAttributeArray.include?(attribute['name'])
        space_sdk.update_user_profile_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_user_profile_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceUserProfileAttributeArray.push(attribute['name'])
  }  
end  

destinationUserProfileAttributeArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceUserProfileAttributeArray.include?(spaceAttribute)
      space_sdk.delete_user_profile_attribute_definition(spaceAttribute)
  end
}


# ------------------------------------------------------------------------------
# Update Team Attributes
# ------------------------------------------------------------------------------

sourceTeamAttributeArray = []
destinationTeamAttributeArray = JSON.parse(space_sdk.find_team_attribute_definitions().content_string)['teamAttributeDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/teamAttributeDefinitions.json")
  teamAttributeDefinitions = JSON.parse(File.read(file))
  teamAttributeDefinitions.each { |attribute|
      if destinationTeamAttributeArray.include?(attribute['name'])
        space_sdk.update_team_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_team_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceTeamAttributeArray.push(attribute['name'])
  }  
end

destinationTeamAttributeArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceTeamAttributeArray.include?(spaceAttribute)
      space_sdk.delete_team_attribute_definition(spaceAttribute)
  end
}


# ------------------------------------------------------------------------------
# Update Datastore Attributes
# ------------------------------------------------------------------------------

sourceDatastoreAttributeArray = []
destinationDatastoreAttributeArray = JSON.parse(space_sdk.find_datastore_form_attribute_definitions().content_string)['datastoreFormAttributeDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/datastoreFormAttributeDefinitions.json")
  datastoreFormAttributeDefinitions = JSON.parse(File.read(file))
  datastoreFormAttributeDefinitions.each { |attribute|
      if destinationDatastoreAttributeArray.include?(attribute['name'])
        space_sdk.update_datastore_form_attribute_definition(attribute['name'], attribute)
      else
        space_sdk.add_datastore_form_attribute_definition(attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceDatastoreAttributeArray.push(attribute['name'])
  }  
end

destinationDatastoreAttributeArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceDatastoreAttributeArray.include?(spaceAttribute)
      space_sdk.delete_datastore_form_attribute_definition(spaceAttribute)
  end
}


# ------------------------------------------------------------------------------
# Update Security Policy
# ------------------------------------------------------------------------------

sourceSecurityPolicyArray = []

destinationSecurityPolicyArray = JSON.parse(space_sdk.find_space_security_policy_definitions().content_string)['securityPolicyDefinitions'].map { |definition|  definition['name']}
if File.file?(file = "#{core_path}/space/securityPolicyDefinitions.json")
  securityPolicyDefinitions = JSON.parse(File.read(file))
  securityPolicyDefinitions.each { |attribute|
      if destinationSecurityPolicyArray.include?(attribute['name'])
        space_sdk.update_space_security_policy_definition(attribute['name'], attribute)
      else
        space_sdk.add_space_security_policy_definition(attribute)
      end
      sourceSecurityPolicyArray.push(attribute['name'])
  }  
end

destinationSecurityPolicyArray.each { | spaceAttribute |
  if vars["options"]["delete"] && !sourceSecurityPolicyArray.include?(spaceAttribute)
      space_sdk.delete_space_security_policy_definition(spaceAttribute)
  end
}


# ------------------------------------------------------------------------------
# import bridge models
# *NOTE* - This if the bridge doesn't exist the model will be imported w/ an empty "Bridge Slug" value.
# ------------------------------------------------------------------------------

destinationModels = space_sdk.find_bridge_models()
destinationModels_Array = JSON.parse(destinationModels.content_string)['models'].map{ |model| model['activeMappingName']}

Dir["#{core_path}/space/models/*.json"].each{ |model|
  body = JSON.parse(File.read(model))
  if destinationModels_Array.include?(body['name'])
    space_sdk.update_bridge_model(body['name'], body)
  elsif
    space_sdk.add_bridge_model(body)
  end
}

# ------------------------------------------------------------------------------
# delete bridge models
# Delete any Bridges from the destination which are missing from the import data
# ------------------------------------------------------------------------------
SourceModelsArray = Dir["#{core_path}/space/models/*.json"].map{ |model| JSON.parse(File.read(model))['name'] }

destinationModels_Array.each do |model|
  if vars["options"]["delete"] && !SourceModelsArray.include?(model)
    space_sdk.delete_bridge_model(model)
  end
end

# ------------------------------------------------------------------------------
# import datastore forms
# ------------------------------------------------------------------------------
destinationDatastoreForms = [] #From destination server
sourceDatastoreForms = [] #From import data

logger.info "Importing datastore forms for #{vars["core"]["space_slug"]}"

  datastoreForms = space_sdk.find_datastore_forms()
  destinationDatastoreForms = JSON.parse(datastoreForms.content_string)['forms'].map{ |model| model['slug']}
  Dir["#{core_path}/space/datastore/forms/*.json"].each { |datastore|
    body = JSON.parse(File.read(datastore))
    sourceDatastoreForms.push(body['slug'])
    if destinationDatastoreForms.include?(body['slug'])
      space_sdk.update_datastore_form(body['slug'], body)
    else
      space_sdk.add_datastore_form(body)
    end
  }

# ------------------------------------------------------------------------------
# delete datastore forms
# Delete any form from the destination which are missing from the import data
# ------------------------------------------------------------------------------


destinationDatastoreForms.each { |datastore_slug|
  if vars["options"]["delete"] && !sourceDatastoreForms.include?(datastore_slug)
    space_sdk.delete_datastore_form(datastore_slug)
  end
}

# ------------------------------------------------------------------------------
# Import Datastore Data
# ------------------------------------------------------------------------------
destinationDatastoreFormSubmissions = {}
sourceDatastoreFormSubmissions = {}

# import kapp & datastore submissions
Dir["#{core_path}/space/datastore/forms/**/submissions*.ndjson"].sort.each do |filename|
  form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
  Array(space_sdk.find_all_form_datastore_submissions(form_slug).content['submissions']).each { |submission|
    space_sdk.delete_datastore_submission(submission['id'])
  }
  File.readlines(filename).each do |line|
    submission = JSON.parse(line)
    body = { 
      "values" => submission["values"],
      "coreState" => submission["coreState"]
    }
    space_sdk.add_datastore_submission(form_slug, body).content
  end
end

# ------------------------------------------------------------------------------
# import space teams
# ------------------------------------------------------------------------------
SourceTeamArray = []
destinationTeamsArray = JSON.parse(space_sdk.find_teams().content_string)['teams'].map{ |team| {"slug" => team['slug'], "name"=>team['name']} }
Dir["#{core_path}/space/teams/*.json"].each{ |team|
  body = JSON.parse(File.read(team))
  if !destinationTeamsArray.find {|destination_team| destination_team['slug'] == body['slug']  }.nil?
    space_sdk.update_team(body['slug'], body)
  else
    space_sdk.add_team(body)
  end
  #Add Attributes to the Team
  body['attributes'].each{ | attribute |
   space_sdk.add_team_attribute(body['name'], attribute['name'], attribute['values'])
  }
  SourceTeamArray.push({'name' => body['name'], 'slug'=>body['slug']} )
}

# ------------------------------------------------------------------------------
# delete space teams
# TODO: A method doesn't exist for deleting the team
# ------------------------------------------------------------------------------

destinationTeamsArray.each do |team|
  #if !SourceTeamArray.include?(team)
  if SourceTeamArray.find {|source_team| source_team['slug'] == team['slug']  }.nil?
    #Delete has been disabled.  It is potentially too dangerous to include w/o advanced knowledge.
    #space_sdk.delete_team(team['slug'])
  end
end


# ------------------------------------------------------------------------------
# import kapp data
# ------------------------------------------------------------------------------

Dir["#{core_path}/space/kapps/*.json"].each { |file|
  kapp = JSON.parse(File.read(file))
  kappExists = space_sdk.find_kapp(kapp['slug']).code.to_i == 200
  
  if kappExists
    space_sdk.update_kapp(kapp['slug'], kapp)
  else
    space_sdk.add_kapp(kapp['name'], kapp['slug'], kapp)
  end

  # ------------------------------------------------------------------------------
  # Migrate Kapp Attribute Definitions
  # ------------------------------------------------------------------------------
  sourceKappAttributeArray = []
  destinationKappAttributeArray = JSON.parse(space_sdk.find_kapp_attribute_definitions(kapp['slug']).content_string)['kappAttributeDefinitions'].map { |definition|  definition['name']}
  kappAttributeDefinitions = JSON.parse(File.read("#{core_path}/space/kapps/#{kapp['slug']}/kappAttributeDefinitions.json"))

  kappAttributeDefinitions.each { |attribute|
      if destinationKappAttributeArray.include?(attribute['name'])
        space_sdk.update_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute)
      else
        space_sdk.add_kapp_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceKappAttributeArray.push(attribute['name'])
  }   

  destinationKappAttributeArray.each { | attribute |
    if vars["options"]["delete"] && !sourceKappAttributeArray.include?(attribute)
        space_sdk.delete_kapp_attribute_definition(kapp['slug'],attribute)
    end
  }
  

  # ------------------------------------------------------------------------------
  # Migrate Kapp Category Definitions
  # ------------------------------------------------------------------------------
  sourceKappCategoryArray = []
  destinationKappAttributeArray = JSON.parse(space_sdk.find_category_attribute_definitions(kapp['slug']).content_string)['categoryAttributeDefinitions'].map { |definition|  definition['name']}
  if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categoryAttributeDefinitions.json")
    kappCategoryDefinitions = JSON.parse(File.read(file))

    kappCategoryDefinitions.each { |attribute|
        if destinationKappAttributeArray.include?(attribute['name'])
          space_sdk.update_category_attribute_definition(kapp['slug'], attribute['name'], attribute)
        else
          space_sdk.add_category_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
        end
        sourceKappCategoryArray.push(attribute['name'])
    }   
  end
  destinationKappAttributeArray.each { | attribute |
    if !sourceKappCategoryArray.include?(attribute)
        space_sdk.delete_category_attribute_definition(kapp['slug'],attribute)
    end
  }

  # ------------------------------------------------------------------------------
  # Migrate Form Attribute Definitions
  # ------------------------------------------------------------------------------
  sourceFormAttributeArray = []
  destinationFormAttributeArray = JSON.parse(space_sdk.find_form_attribute_definitions(kapp['slug']).content_string)['formAttributeDefinitions'].map { |definition|  definition['name']}
  formAttributeDefinitions = JSON.parse(File.read("#{core_path}/space/kapps/#{kapp['slug']}/formAttributeDefinitions.json"))

  formAttributeDefinitions.each { |attribute|
      if destinationFormAttributeArray.include?(attribute['name'])
        space_sdk.update_form_attribute_definition(kapp['slug'], attribute['name'], attribute)
      else
        space_sdk.add_form_attribute_definition(kapp['slug'], attribute['name'], attribute['description'], attribute['allowsMultiple'])
      end
      sourceFormAttributeArray.push(attribute['name'])
  }   

  destinationFormAttributeArray.each { | attribute |
    if vars["options"]["delete"] && !sourceFormAttributeArray.include?(attribute)
        space_sdk.delete_form_attribute_definition(kapp['slug'],attribute)
    end
  }

  # ------------------------------------------------------------------------------
  # Migrate Security Policy Definitions
  # ------------------------------------------------------------------------------
  sourceSecurtyPolicyArray = []
  destinationSecurtyPolicyArray = JSON.parse(space_sdk.find_security_policy_definitions(kapp['slug']).content_string)['securityPolicyDefinitions'].map { |definition|  definition['name']}
  securityPolicyDefinitions = JSON.parse(File.read("#{core_path}/space/kapps/#{kapp['slug']}/securityPolicyDefinitions.json"))

  securityPolicyDefinitions.each { |attribute|
      if destinationSecurtyPolicyArray.include?(attribute['name'])
        space_sdk.update_security_policy_definition(kapp['slug'], attribute['name'], attribute)
      else
        space_sdk.add_security_policy_definition(kapp['slug'], attribute)
      end
      sourceSecurtyPolicyArray.push(attribute['name'])
  }   

  destinationSecurtyPolicyArray.each { | attribute |
    if vars["options"]["delete"] && !sourceSecurtyPolicyArray.include?(attribute)
        space_sdk.delete_security_policy_definition(kapp['slug'],attribute)
    end
  }
   
 # ------------------------------------------------------------------------------
# Migrate Categories on the Kapp
# TODO: Add code for find, update, and delete when methods are available in the SDK
# ------------------------------------------------------------------------------
sourceCategoryArray = []
#destinationCategoryArray = JSON.parse(space_sdk.find_categories(kapp['slug']).content_string)['securityPolicyDefinitions'].map { |definition|  definition['name']}

if File.file?(file = "#{core_path}/space/kapps/#{kapp['slug']}/categories.json")
  categories = JSON.parse(File.read(file))
  categories.each { |attribute|
    #if destinationCategoryArray.include?(attribute['name'])
    # update_category_on_kapp Does not exist as a method in the SDK yet
    #  space_sdk.update_category_on_kapp(attribute)
    #else
      space_sdk.add_category_on_kapp(kapp['slug'], attribute)
    #end
    sourceCategoryArray.push(attribute['name'])
  }
end

# ------------------------------------------------------------------------------
# Delete Categories on the Kapp
# TODO: Add code for delete when methods are available in the SDK
# ------------------------------------------------------------------------------
 
#destinationCategoryArray.each { | attribute |
#  if !sourceCategoryArray.include?(attribute)
#      space_sdk.delete_security_policy_definition(kapp['slug'],attribute)
#  end
#}

# ------------------------------------------------------------------------------
# import space webhooks
# ------------------------------------------------------------------------------
sourceSpaceWebhooksArray = []
destinationSpaceWebhooksArray = JSON.parse(space_sdk.find_webhooks_on_space().content_string)['webhooks'].map{ |webhook| webhook['name']}

Dir["#{core_path}/space/webhooks/*.json"].each{ |file|
  webhook = JSON.parse(File.read(file))
  if destinationSpaceWebhooksArray.include?(webhook['name'])
     space_sdk.update_webhook_on_space(webhook['name'], webhook)
  elsif
    space_sdk.add_webhook_on_space(webhook)
  end
  sourceSpaceWebhooksArray.push(webhook['name'])
}

# ------------------------------------------------------------------------------
# delete space webhooks
# TODO: A method doesn't exist for deleting the webhook
# ------------------------------------------------------------------------------

destinationSpaceWebhooksArray.each do |webhook|
  if vars["options"]["delete"] && !sourceSpaceWebhooksArray.include?(webhook)
    space_sdk.delete_webhook_on_space(webhook)
  end
end  

  # ------------------------------------------------------------------------------
  # Migrate Kapp Webhooks
  # ------------------------------------------------------------------------------
  sourceWebhookArray = []
  webhooks_on_kapp = space_sdk.find_webhooks_on_kapp(kapp['slug']) 
  
  if webhooks_on_kapp.code=="200" 
    destinationWebhookArray = JSON.parse(webhooks_on_kapp.content_string)['webhooks'].map { |definition|  definition['name']}
    Dir["#{core_path}/space/kapps/#{kapp['slug']}/webhooks/*.json"].each{ |webhookFile|
        webhookDef = JSON.parse(File.read(webhookFile))
        if destinationWebhookArray.include?(webhookDef['name'])
          space_sdk.update_webhook_on_kapp(kapp['slug'], webhookDef['name'], webhookDef)
        else
          space_sdk.add_webhook_on_kapp(kapp['slug'], webhookDef)
        end
        sourceWebhookArray.push(webhookDef['name'])
    }   
  
    # ------------------------------------------------------------------------------
    # delete Kapp Webhooks
    # ------------------------------------------------------------------------------
    destinationWebhookArray.each { | attribute |
      if vars["options"]["delete"] && !sourceWebhookArray.include?(attribute)
          space_sdk.delete_webhook_on_kapp(kapp['slug'],attribute)
      end
    }
  end                                                        


  # ------------------------------------------------------------------------------
  # add forms
  # ------------------------------------------------------------------------------
  
  sourceForms = [] #From import data
  destinationForms = JSON.parse(space_sdk.find_forms(kapp['slug']).content_string)['forms'].map{ |form| form['slug']}
  
  Dir["#{core_path}/space/kapps/#{kapp['slug']}/forms/*.json"].each { |form|
    properties = File.read(form)
    form = JSON.parse(properties)
    sourceForms.push(form['slug'])
    if destinationForms.include?(form['slug'])
      space_sdk.update_form(kapp['slug'] ,form['slug'], properties)
    else
      space_sdk.add_form(kapp['slug'], properties)
    end
  }
  
  # ------------------------------------------------------------------------------
  # delete forms
  # Delete any form from the destination which are missign from the import data
  # ------------------------------------------------------------------------------

  destinationForms.each { |form|
    if vars["options"]["delete"] && !sourceForms.include?(form)
      space_sdk.delete_form(kapp['slug'], form)
    end
  } 
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
task_sdk.import_handlers(true) 

# ------------------------------------------------------------------------------
# Import Task Trees and Routines
# ------------------------------------------------------------------------------

# import routines and force overwrite
task_sdk.import_routines(true)
# import trees and force overwrite
task_sdk.import_trees(true)




# ------------------------------------------------------------------------------
# Delete Trees and Routines not in the Source Data
# ------------------------------------------------------------------------------

# identify Trees and Routines on destination
destinationtrees = []
trees = JSON.parse(task_sdk.find_trees().content_string)
trees['trees'].each { |tree|
  destinationtrees.push( tree['title'] )
}

# identify Routines in source data
sourceTrees = []
Dir["#{task_path}/routines/*.xml"].each {|routine| 
  doc = Document.new(File.new(routine))
  root = doc.root
  sourceTrees.push("#{root.elements["taskTree/name"].text}")
}
# identify trees in source data
Dir["#{task_path}/sources/*"].each {|source| 
  if File.directory? source
    Dir["#{source}/trees/*.xml"].each { |tree|
      doc = Document.new(File.new(tree))
      root = doc.root
      tree = "#{root.elements["sourceName"].text} :: #{root.elements["sourceGroup"].text} :: #{root.elements["taskTree/name"].text}"
      sourceTrees.push(tree)
    }
  end
}

# Delete the extra tress and routines on the source  
destinationtrees.each { | tree |
  if vars["options"]["delete"] && !sourceTrees.include?(tree)
    treeDef = tree.split(' :: ')
    task_sdk.delete_tree(  tree  )
  end
}

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
