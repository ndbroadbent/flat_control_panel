set :application, "octopus_access_control"
set :hostname, "lock-10c"
set :user, "tc"

set :local_path, File.dirname(__FILE__)
set :transfer_to, "/tmp"
set :deploy_to, "/mnt/sda1"
set :shared_path, "#{deploy_to}/shared"
set :current_path, "#{deploy_to}/#{application}"

# ------------------------------------------------------
desc "Package application"
task :build_package do
  puts "== Packaging application..."
  %x[cd #{local_path} && \
    tar -czpvf /tmp/#{application}.tar.gz #{local_path} --exclude=.git]
  puts "===== #{application}.tar.gz was created."
end

# ------------------------------------------------------
desc "Transfer package to target"
task :transfer_package do
  puts "== Transferring to Evo T20 (#{hostname})..."
  %x[scp /tmp/#{application}.tar.gz #{user}@#{hostname}:#{transfer_to}]
  puts "===== Package transferred."
end

# ------------------------------------------------------
desc "Install the application on your iPhone"
task :install, :hosts => "#{hostname}" do
  run <<-CMD
    sudo rm -rf #{current_path};
    sudo mkdir -p #{current_path};
    cd #{current_path};
    sudo tar -xzpvf #{transfer_to}/#{application}.tar.gz;
    rm -f #{transfer_to}/#{application}.tar.gz;
  CMD
end

# ------------------------------------------------------
desc "Symlink shared config files"
task :symlink_shared, :hosts => "#{hostname}" do
  sudo "ln -fs #{shared_path}/config.yml #{current_path}/config/"
  sudo "ln -fs #{shared_path}/authorized_users.yml #{current_path}/config/"
  sudo "ln -fs #{shared_path}/user_radio_prefs.yml #{current_path}/config/"
end

# ------------------------------------------------------
namespace :processes do
  desc "Kill running processes"
  task :stop, :hosts => "#{hostname}" do;  run "cd #{current_path} && sudo ./script/stop_processes.sh";  end
  # ------------------------------------------------------
  desc "Start processes"
  task :start, :hosts => "#{hostname}" do; run "cd #{current_path} && sudo ./script/start_processes.sh &"; end
  # ------------------------------------------------------
  desc "Restart processes"
  task :restart, :hosts => "#{hostname}" do; stop; start; end
end

# ------------------------------------------------------
desc "Update time from internet"
task :update_time, :hosts => "#{hostname}" do
  sudo "getTime.sh"
end

# ------------------------------------------------------
desc "Package and install the application on your iPhone"
task :deploy, :hosts => "#{hostname}" do
  build_package
  transfer_package
  install
  symlink_shared
  processes.restart
end

