set :application, "octopus_access_control"
set :repository,  "https://github.com/ndbroadbent/flat_control_panel.git"
set :scm, :git
set :user, "tc"
server "lock-10c", :app
set :deploy_to, "/mnt/sda1/#{application}"

set :keep_releases, 2

# Helper method which prompts for user input
def prompt_with_default(prompt, var, default)
  set(var) do
    Capistrano::CLI.ui.ask "#{prompt} [#{default}]: "
  end
  set var, default if eval("#{var.to_s}.empty?")
end

# ---------------------------------------------------
#                 Before / After Hooks
# ---------------------------------------------------

after "deploy",        "deploy:symlink_shared"
after "deploy:update", "deploy:cleanup"
after "deploy:cold",   "deploy:create_shared_dirs"
after "deploy:cold",   "deploy:setup"
after "deploy:setup",  "deploy:symlink_shared"

# ---------------------------------------------------
#                   Deploy Tasks
# ---------------------------------------------------

namespace :deploy do
  desc "Symlink shared files"
  task :symlink_shared do
    run "ln -nfs #{shared_path}/config/config.yml #{current_path}/config/config.yml"
  end

  desc "Create dir structure"
  task :create_shared_dirs do
    run "mkdir -p #{shared_path}/config"
  end
end

# ---------------------------------------------------
#                   Install Tasks
# ---------------------------------------------------

namespace :processes do
  desc "Restart processes"
  task :restart do
  end
end

# ---------------------------------------------------
#         Create / Update Config & Version
# ---------------------------------------------------

#namespace :setup do
#  desc "Create or update XBMC config.yml"
#  task :config do
#    prompt_with_default "XBMC URI:",      "base_uri", ""
#    prompt_with_default "XBMC Username:", "username", "xbmc"
#    prompt_with_default "XBMC Password:", "password", ""
#    xbmc_api_config = <<-EOF
#---
#:base_uri: #{base_uri}
#:username: #{username}
#:password: #{password}
#EOF
#    put xbmc_api_config, "#{shared_path}/config/config.yml"
#    puts "== Successfully created \"#{shared_path}/config/config.yml\""
#  end
#end

