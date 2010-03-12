set :application, "LinkedLCCN"
set :repository,  "git@github.com:rsinger/LinkedLCCN.git"

set :scm, :git
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`

role :web, "anvil.lisforge.net"                          # Your HTTP server, Apache/etc
role :app, "anvil.lisforge.net"                          # This may be the same as your `Web` server
role :db,  "anvil.lisforge.net", :primary => true # This is where Rails migrations will run
#role :db,  "your slave db-server here"
set :deploy_to, "/home/rsinger/rails-sites/#{application}"
# If you are using Passenger mod_rails uncomment this:
# if you're still using the script/reapear helper you will need
# these http://github.com/rails/irs_process_scripts
set :user, 'rsinger'
set :use_sudo, true
set(:password) { Capistrano::CLI.ui.ask("Password: ") }
default_run_options[:pty] = true


namespace :deploy do
  task :symlink_shared do
    run "ln -s #{deploy_to}/shared/config/config.yml #{current_path}/config/"
  end  
  task :start do ; end
  task :stop do ; end
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
  end
end

namespace :rake do
 desc "Run a task on a remote server."
 # run like: cap staging rake:invoke task=a_certain_task
 task :invoke do
  run("cd #{deploy_to}/current; /usr/bin/rake #{ENV['task']}")
 end
end

namespace :delayed_job do
  task :start_workers do
    run("cd #{deploy_to}/current; nohup /usr/bin/ruby ./script/job_runner.rb &")
  end
  task :stop_workers do
    if run("cat #{deploy_to}/current/tmp/dj.pid")
      run("kill -9 `cat #{deploy_to}/current/tmp/dj.pid`")
    end
  end
end

#before "deploy:restart", "delayed_job:stop_workers"
#after "deploy:restart", "delayed_job:start_workers"
after "deploy:update", "deploy:symlink_shared"