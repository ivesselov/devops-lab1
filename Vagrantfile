NODES = {
  "etcd01"  => { ip: "192.168.56.10", mem: 1024, cpus: 1, ports: { 5432 => 5432 } },
  "pgsql01" => { ip: "192.168.56.11", mem: 1536, cpus: 1, ports: { 5432 => 6432 } },
  "pgsql02" => { ip: "192.168.56.12", mem: 1536, cpus: 1, ports: { 5432 => 7432 } },
  "k3s01"   => { ip: "192.168.56.20", mem: 4096, cpus: 2, ports: { 80 => 80, 443 => 443 } },
}

ANSIBLE_KEY = "keys/ansible_ed25519"
HOSTS = NODES.map { |name, n| "#{n[:ip]} #{name}" }.join("\n")

Vagrant.configure("2") do |config|
  config.vm.box     = "oraclelinux/9"
  config.vm.box_url = "https://oracle.github.io/vagrant-projects/boxes/oraclelinux/9.json"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider :libvirt do |lv|
    lv.management_network_mtu = 1460
  end

  NODES.each do |name, n|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.network "private_network", ip: n[:ip]

      n[:ports].each do |guest, host|
	node.vm.network "forwarded_port", guest: guest, host: host, host_ip: "127.0.0.1"
      end

      node.vm.provider :libvirt do |lv|
        lv.memory = n[:mem]
        lv.cpus   = n[:cpus]
      end

      node.vm.provision "file", source: "#{ANSIBLE_KEY}.pub", destination: "/tmp/ansible.pub"
      node.vm.provision "shell", inline: <<-SHELL
        set -e
        grep -q "#{n[:ip]} #{name}" /etc/hosts || cat >> /etc/hosts <<EOF
#{HOSTS}
EOF
        id ansible &>/dev/null || useradd -m -s /bin/bash ansible
        install -d -m 700 -o ansible -g ansible /home/ansible/.ssh
        install -m 600 -o ansible -g ansible /tmp/ansible.pub /home/ansible/.ssh/authorized_keys
        echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
        chmod 440 /etc/sudoers.d/ansible
        rm -f /tmp/ansible.pub
      SHELL

      if name == "k3s01"
        node.vm.provision "file", source: ANSIBLE_KEY, destination: "/tmp/ansible_key"
        node.vm.provision "shell", inline: <<-SHELL
          set -e
          dnf install -y ansible-core
          install -m 600 -o ansible -g ansible /tmp/ansible_key /home/ansible/.ssh/id_ed25519
          rm -f /tmp/ansible_key
        SHELL
      end
    end
  end
end
