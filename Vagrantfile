Vagrant.configure("2") do |config|

    config.vm.box = "debian/bookworm64"
    
    config.vm.define "p3" do |server|
        server.vm.hostname = "p3"

        server.vm.network "private_network", ip: "192.168.56.110"
        server.vm.network "forwarded_port", guest: 8443, host: 8443
        server.vm.network "forwarded_port", guest: 8888, host: 8888

        server.vm.provider "virtualbox" do |vb|
            vb.name = "p3"
            vb.memory = "3072"
            vb.cpus = 3
        end

        server.vm.synced_folder ".", "/vagrant"

        server.vm.provision "shell", path: "scripts/init-machine.sh"
        server.vm.provision "shell", path: "scripts/setup.sh"
    end
end
