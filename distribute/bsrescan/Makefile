all:
	mkdir -p obj
	g++ -o obj/main main.cpp -pedantic -Wall
install: all
	sudo chown root:root obj/main
	sudo mkdir -p /opt/bluespecpcie_manager
	sudo cp obj/main /opt/bluespecpcie_manager/bsrescan
	sudo chmod 4755 /opt/bluespecpcie_manager/bsrescan
