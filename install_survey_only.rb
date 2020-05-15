# Action options must be passed as a JSON string
#
# Format with example values:
#
# {
#   "agent" => {
#     "component_type" => "agent",
#     "bridge_api" => "/app/api/v1/bridges",
#     "bridge_path" => "/app/api/v1/bridges/bridges/kinetic-core",
#     "bridge_slug" => "kinetic-core",
#     "filestore_api" => "/app/api/v1/filestores"
#   },
#   "core" => {
#     "api" => "http://localhost:8080/kinetic/app/api/v1",
#     "agent_api" => "http://localhost:8080/kinetic/foo/app/components/agent/app/api/v1",
#     "proxy_url" => "http://localhost:8080/kinetic/foo/app/components",
#     "server" => "http://localhost:8080/kinetic",
#     "space_slug" => "foo",
#     "space_name" => "Foo",
#     "service_user_username" => "service_user_username",
#     "service_user_password" => "secret",
#     "task_api_v1" => "http://localhost:8080/kinetic/foo/app/components/task/app/api/v1",
#     "task_api_v2" => "http://localhost:8080/kinetic/foo/app/components/task/app/api/v2"
#   },
#   "discussions" => {
#     "api" => "http://localhost:8080/app/discussions/api/v1",
#     "server" => "http://localhost:8080/app/discussions",
#     "space_slug" => "foo"
#   },
#   "task" => {
#     "api" => "http://localhost:8080/kinetic-task/app/api/v1",
#     "api_v2" => "http://localhost:8080/kinetic-task/app/api/v2",
#     "component_type" => "task",
#     "server" => "http://localhost:8080/kinetic-task",
#     "space_slug" => "foo",
#     "signature_secret" => "1234asdf5678jkl;"
#   },
#   "http_options" => {
#     "log_level" => "info",
#     "gateway_retry_limit" => 5,
#     "gateway_retry_delay" => 1.0,
#     "ssl_ca_file" => "/app/ssl/tls.crt",
#     "ssl_verify_mode" => "peer"
#   },
#   "data" => {
#     "requesting_user" => {
#       "username" => "joe.user",
#       "displayName" => "Joe User",
#       "email" => "joe.user@google.com",
#     },
#     "users" => [
#       {
#         "username" => "joe.user"
#       }
#     ],
#     "space" => {
#       "attributesMap" => {
#         "Platform Host URL" => [ "http://localhost:8080" ]
#       }
#     },
#     "handlers" => {
#       "kinetic_core_system_api_v1" => {
#         "api_username" => "admin",
#         "api_password" => "password",
#         "api_location" => "http://localhost:8080/app/api/v1"
#       }
#     }
#     "smtp" => {
#       "server" => "smtp.gmail.com",
#       "port" => "587",
#       "tls" => "true",
#       "username" => "joe.blow@gmail.com",
#       "password" => "test",
#       "from_address" => "wally@kinops.io"
#     }
#   }
# }

require "logger"
require "json"

template_name = "platform-template-survey"
kapp_name = "Survey"
kapp_slug = "survey"

logger = Logger.new(STDERR)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  date_format = datetime.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  "[#{date_format}] #{severity}: #{msg}\n"
end

raise "Missing JSON argument string passed to template install script" if ARGV.empty?
begin
  vars = JSON.parse(ARGV[0])
  # initialize the data property unless it already exists
  vars["data"] = {} unless vars.has_key?("data")
rescue => e
  raise "Template #{template_name} install error: #{e.inspect}"
end

# determine the directory paths
platform_template_path = File.dirname(File.expand_path(__FILE__))
core_path = File.join(platform_template_path, "core")
task_path = File.join(platform_template_path, "task")

# ------------------------------------------------------------------------------
# setup
# ------------------------------------------------------------------------------

logger.info "Installing gems for the \"#{template_name}\" template."
Dir.chdir(platform_template_path) { system("bundle", "install") }

require "kinetic_sdk"

# ------------------------------------------------------------------------------
# common
# ------------------------------------------------------------------------------

http_options = (vars["http_options"] || {}).each_with_object({}) do |(k, v), result|
  result[k.to_sym] = v
end

# ------------------------------------------------------------------------------
# core
# ------------------------------------------------------------------------------

space_sdk = KineticSdk::Core.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{core_path}" }),
})

kapp_path = "#{core_path}/kapps/survey"

# parse kapp from file
kapp = JSON.parse(File.read("#{core_path}/kapps/survey.json"))

# add formAttributeDefinitions
kapp['formAttributeDefinitions'] =
    JSON.parse(File.read("#{kapp_path}/formAttributeDefinitions.json"))

# add kappAttributeDefinitions
kapp['kappAttributeDefinitions'] =
    JSON.parse(File.read("#{kapp_path}/kappAttributeDefinitions.json"))

# create the kapp
space_sdk.add_kapp(kapp_name, kapp_slug, kapp)

# import security policy definitions
space_sdk.delete_security_policy_definitions(kapp_slug)
JSON.parse(File.read("#{kapp_path}/securityPolicyDefinitions.json")).each do |policy|
    space_sdk.add_security_policy_definition(kapp_slug, {
        "name" => policy['name'],
        "message" => policy['message'],
        "rule" => policy['rule'],
        "type" => policy['type']
    })
end

# import forms
Dir["#{kapp_path}/forms/*"].each do |form|
    space_sdk.add_form(kapp_slug, JSON.parse(File.read("#{form}")))
end

# import webhooks
Dir["#{kapp_path}/webhooks/*"].each do |webhook|
    space_sdk.add_webhook_on_kapp(kapp_slug, JSON.parse(File.read("#{webhook}")))
end



# create required teams
team = JSON.parse(File.read("#{core_path}/teams/Role::Survey Initiator.json"))
space_sdk.add_team()

logger.info "Installing the core components for the \"#{template_name}\" template."
logger.info "  installing with api: #{space_sdk.api_url}"

# import the space for the template
space_sdk.import_space(vars["core"]["space_slug"])

# set space attributes
space_attributes_map = {
  "Discussion Id" => [""],
  "Task Server Scheme" => [URI(vars["task"]["server"]).scheme],
  "Task Server Host" => [URI(vars["task"]["server"]).host],
  "Task Server Space Slug" => [vars["task"]["space_slug"]],
  "Task Server Url" => [vars["task"]["server"]],
  "Web Server Url" => [vars["core"]["server"]],
}
# set space attributes passed in the variable data
vars_space_attributes_map = (vars["data"].has_key?("space") &&
                             vars["data"]["space"].has_key?("attributesMap")) ?
  vars["data"]["space"]["attributesMap"] : {}
# merge in any space attributes passed in the variable data
space_attributes_map = space_attributes_map.merge(vars_space_attributes_map)

# update the space properties
#   set required space attributes
#   set space name from vars
space_sdk.update_space({
  "attributesMap" => space_attributes_map,
  "name" => vars["core"]["space_name"],
})

# import kapp & datastore submissions
Dir["#{core_path}/**/*.ndjson"].sort.each do |filename|
  is_datastore = filename.include?("/datastore/forms/")
  form_slug = filename.match(/forms\/(.+)\/submissions\.ndjson/)[1]
  kapp_slug = filename.match(/kapps\/(.+)\/forms/)[1] if !is_datastore

  File.readlines(filename).each do |line|
    submission = JSON.parse(line)
    body = { "values" => submission["values"] }
    is_datastore ?
      space_sdk.add_datastore_submission(form_slug, body).content :
      space_sdk.add_submission(kapp_slug, form_slug, body).content
  end
end

# update kinetic task webhook endpoints to point to the correct task server
space_sdk.find_webhooks_on_space.content["webhooks"].each do |webhook|
  url = webhook["url"]
  # if the webhook contains a kinetic task endpoint
  if url.include?("/kinetic-task/app/api/v1")
    # replace the server/host portion
    apiIndex = url.index("/app/api/v1")
    url = url.sub(url.slice(0..apiIndex - 1), vars["task"]["server"])
    # update the webhook
    space_sdk.update_webhook_on_space(webhook["name"], {
      "url" => url,
      "authStrategy" => {},
    })
  end
end
space_sdk.find_kapps.content["kapps"].each do |kapp|
  space_sdk.find_webhooks_on_kapp(kapp["slug"]).content["webhooks"].each do |webhook|
    url = webhook["url"]
    # if the webhook contains a kinetic task endpoint
    if url.include?("/kinetic-task/app/api/v1")
      # replace the server/host portion
      apiIndex = url.index("/app/api/v1")
      url = url.sub(url.slice(0..apiIndex - 1), vars["task"]["server"])
      # update the webhook
      space_sdk.update_webhook_on_kapp(kapp["slug"], webhook["name"], {
        "url" => url,
        "authStrategy" => {},
      })
    end
  end
end

# update each bridge model mapping with the corresponding bridge in the agent platform component
space_sdk.find_bridge_models.content["models"].each do |model|
  exported_model = space_sdk.find_bridge_model(model["name"], { "export" => true }).content["model"]
  exported_model["mappings"].each do |mapping|
    mapping.delete("bridgeName")
    mapping["bridgeSlug"] = "kinetic-core"
    space_sdk.update_bridge_model_mapping(model["name"], mapping["name"], mapping)
  end
end

# create or update oAuth clients
[oauth_client_prod_bundle, oauth_client_dev_bundle, oauth_client_service_user].each do |client|
  if space_sdk.find_oauth_client(client["clientId"]).status == 404
    space_sdk.add_oauth_client(client)
  else
    space_sdk.update_oauth_client(client["clientId"], client)
  end
end

# create any additional users that were specified
(vars["data"]["users"] || []).each do |user|
  space_sdk.add_user(user)
end

# ------------------------------------------------------------------------------
# task
# ------------------------------------------------------------------------------

task_sdk = KineticSdk::Task.new({
  app_server_url: "#{vars["core"]["proxy_url"]}/task",
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: http_options.merge({ export_directory: "#{task_path}" }),
})

logger.info "Installing the task components for the \"#{template_name}\" template."
logger.info "  installing with api: #{task_sdk.api_url}"

# cleanup playground data
task_sdk.delete_categories
task_sdk.delete_groups
task_sdk.delete_users
task_sdk.delete_policy_rules

# import access keys
Dir["#{task_path}/access-keys/*.json"].each do |file|
  # parse the access_key file
  required_access_key = JSON.parse(File.read(file))
  # determine if access_key is already installed
  not_installed = task_sdk.find_access_key(required_access_key["identifier"]).status == 404
  # set access key secret
  required_access_key["secret"] = "SETME"
  # add or update the access key
  not_installed ?
    task_sdk.add_access_key(required_access_key) :
    task_sdk.update_access_key(required_access_key["identifier"], required_access_key)
end

# import data from template and force overwrite where necessary
task_sdk.import_groups
task_sdk.import_handlers(true)
task_sdk.import_policy_rules

# import sources
Dir["#{task_path}/sources/*.json"].each do |file|
  # parse the source file
  required_source = JSON.parse(File.read(file))
  # determine if source is already installed
  not_installed = task_sdk.find_source(required_source["name"]).status == 404
  # set source properties
  required_source["properties"] = task_source_properties[required_source["name"]] || {}
  # add or update the source
  not_installed ? task_sdk.add_source(required_source) : task_sdk.update_source(required_source)
end

task_sdk.import_routines(true)
task_sdk.import_categories

# import trees and force overwrite
task_sdk.import_trees(true)

# configure handler info values
task_sdk.find_handlers.content["handlers"].each do |handler|
  handler_definition_id = handler["definitionId"]

  if task_handler_configurations.has_key?(handler_definition_id)
    logger.info "Updating handler #{handler_definition_id}"
    task_sdk.update_handler(handler_definition_id, {
      "properties" => task_handler_configurations[handler_definition_id],
    })
  else
    if handler_definition_id.start_with?("kinetic_core_api_v1")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["api"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
        },
      })
    elsif handler_definition_id.start_with?("kinetic_discussions_api_v1")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_oauth_location" => "#{vars["core"]["server"]}/app/oauth/token?grant_type=client_credentials&response_type=token",
          "api_location" => vars["discussions"]["api"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
        },
      })
    elsif handler_definition_id.start_with?("kinetic_task_api_v1")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["task_api_v1"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
          "api_access_key_identifier" => nil,
          "api_access_key_secret" => nil,
        },
      })
    elsif handler_definition_id.start_with?("kinetic_task_api_v2")
      logger.info "Updating handler #{handler_definition_id}"
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_location" => vars["core"]["task_api_v2"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
        },
      })
    elsif handler_definition_id.start_with?("kinetic_request_ce_notification_template_send_v")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => task_handler_configurations["kinetic_request_ce_notification_template_send"],
      })
    elsif handler_definition_id.start_with?("smtp_email_send")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => task_handler_configurations["smtp_email_send"],
      })
    elsif handler_definition_id.start_with?("kinetic_request_ce")
      task_sdk.update_handler(handler_definition_id, {
        "properties" => {
          "api_server" => vars["core"]["server"],
          "api_username" => vars["core"]["service_user_username"],
          "api_password" => vars["core"]["service_user_password"],
          "space_slug" => nil,
        },
      })
    end
  end
end

# update the engine properties
task_sdk.update_engine({
  "Max Threads" => "2",
  "Sleep Delay" => "1",
  "Trigger Query" => "'Selection Criterion'=null",
})

# ------------------------------------------------------------------------------
# service portal specific
# ------------------------------------------------------------------------------

# create requesting user that was specified
if (vars["data"]["requesting_user"])
  space_sdk.add_user({
    "username" => vars["data"]["requesting_user"]["username"],
    "email" => vars["data"]["requesting_user"]["email"],
    "displayName" => vars["data"]["requesting_user"]["displayName"],
    "password" => KineticSdk::Utils::Random.simple(16),
    "enabled" => true,
    "spaceAdmin" => true,
    "memberships" => [
      { "team" => { "name" => "Administrators" } },
      { "team" => { "name" => "Default" } },
      { "team" => { "name" => "Role::Form Developer" } },
      { "team" => { "name" => "Role::Task Developer" } },
      { "team" => { "name" => "Role::Data Admin" } },
      { "team" => { "name" => "Role::Employee" } },
      { "team" => { "name" => "Role::Submission Support" } },
    ],
    "profileAttributesMap" => { "Guided Tour" => ["Welcome Tour", "Services", "Queue"] },
  })
end

# temporarily disable webooks while provisioning requesting user / teams
space_sdk.find_webhooks_on_space.content["webhooks"].each do |webhook|
  filter = webhook["filter"].empty? ? "false" : "false && #{webhook["filter"]}"
  space_sdk.update_webhook_on_space(webhook["name"], {
    "filter" => filter,
  })
end
space_sdk.find_kapps.content["kapps"].each do |kapp|
  space_sdk.find_webhooks_on_kapp(kapp["slug"]).content["webhooks"].each do |webhook|
    filter = webhook["filter"].empty? ? "false" : "false && #{webhook["filter"]}"
    space_sdk.update_webhook_on_kapp(kapp["slug"], webhook["name"], {
      "filter" => filter,
    })
  end
end

# Create a Discussion SDK connection for the requester user
discussions_options = http_options.merge({
  oauth_client_id: oauth_client_prod_bundle["clientId"],
  oauth_client_secret: oauth_client_prod_bundle["clientSecret"],
})
discussions_sdk = KineticSdk::Discussions.new({
  space_server_url: vars["core"]["server"],
  space_slug: vars["core"]["space_slug"],
  username: vars["core"]["service_user_username"],
  password: vars["core"]["service_user_password"],
  options: discussions_options,
})

# Keep track of which discussions to invite the requester to
requester_discussion_ids = []

# Create an 'All Company' discussion
all_company_discussion = discussions_sdk.add_discussion({
  "title" => "All Company",
  "description" => "All Company Discussion",
  "owningUsers" => [
    { "username": vars["data"]["requesting_user"]["username"] },
  ],
}).content["discussion"]

# Create an initial message in the 'All Company' discussion
discussions_sdk.add_message(all_company_discussion["id"], "Welcome to kinops!!!")
# Set the value of the "Discussion Id" Space attribute
space_sdk.add_space_attribute("Discussion Id", all_company_discussion["id"])
# Add the requester to the space discussion
requester_discussion_ids.unshift(all_company_discussion["id"])

# For each of the teams
(space_sdk.find_teams.content["teams"] || []).each do |team|

  # Skip if the team is a Role
  next if team["name"].start_with?("Role::")

  # Create a team discussion
  discussion = discussions_sdk.add_discussion({
    "title" => team["name"],
    "description" => "#{team["name"]} Discussion",
    "owningTeams" => [
      { "name": team["name"] },
    ],
  }).content["discussion"]

  # Create an initial message in the team discussion
  discussions_sdk.add_message(discussion["id"], "Welcome to the #{team["name"]} Team!!!")
  # Add the team as a related item to the discussion
  discussions_sdk.add_related_item(discussion["id"], "Team", team["slug"])
  # Set the value of the "Discussion Id" Space attribute
  space_sdk.add_team_attribute(team["name"], "Discussion Id", discussion["id"])
  # Add the requester to the team discussion
  if ["Administrators", "Default"].include?(team["name"])
    requester_discussion_ids.unshift(discussion["id"])
  end
end

# Generate appropriate discussion invites for the requester
requester_discussion_ids.each do |discussion_id|
  discussions_sdk.add_invitation_by_username(discussion_id, vars["data"]["requesting_user"]["username"])
end

# re-enable webooks while provisioning requesting user / teams
space_sdk.find_webhooks_on_space.content["webhooks"].each do |webhook|
  filter = webhook["filter"].start_with?("false && ") ? webhook["filter"].gsub("false && ", "") : ""
  space_sdk.update_webhook_on_space(webhook["name"], {
    "filter" => filter,
  })
end
space_sdk.find_kapps.content["kapps"].each do |kapp|
  space_sdk.find_webhooks_on_kapp(kapp["slug"]).content["webhooks"].each do |webhook|
    filter = webhook["filter"].start_with?("false && ") ? webhook["filter"].gsub("false && ", "") : ""
    space_sdk.update_webhook_on_kapp(kapp["slug"], webhook["name"], {
      "filter" => filter,
    })
  end
end

# ------------------------------------------------------------------------------
# complete
# ------------------------------------------------------------------------------

logger.info "Finished installing the \"#{template_name}\" template."
