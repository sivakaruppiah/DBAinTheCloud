
## network public ip

resource "azurerm_public_ip" "pip1" {
  count                   = "${var.server_count}"
  name                    = "${var.prefix}-ado${count.index + 1}-pip1"
  location                = var.location
  resource_group_name     = var.rg_name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

  tags = merge(var.tags, map("FirstApply", timestamp(), "LastApply", timestamp()))

  lifecycle {
    ignore_changes = [tags.FirstApply]
  }
}

## network interface

resource "azurerm_network_interface" "nic1" {
  count               = "${var.server_count}"
  name                = "${var.prefix}-ado${count.index + 1}-nic1"
  location            = var.location
  resource_group_name = var.rg_name
  dns_servers         = ["${var.dc_ip}"]

  ip_configuration {
    name                          = "${var.prefix}-ado${count.index + 1}-ip1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.pip1.*.id, count.index)}"
  }

  tags = merge(var.tags, map("FirstApply", timestamp(), "LastApply", timestamp()))

  lifecycle {
    ignore_changes = [tags.FirstApply]
  }
}

# create virtual machine
resource "azurerm_virtual_machine" "vm1" {
  count                         = "${var.server_count}"
  name                          = "${var.prefix}-ado${count.index + 1}"
  location                      = var.location
  resource_group_name           = var.rg_name
  network_interface_ids         = ["${element(azurerm_network_interface.nic1.*.id, count.index)}"]
  vm_size                       = var.vm_size
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter-smalldisk-g2"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}-ado${count.index + 1}-disk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}-ado${count.index + 1}"
    admin_username = var.adminusername
    admin_password = var.adminpassword
  }

  os_profile_windows_config {
    provision_vm_agent = true
  }

  tags = merge(var.tags, map("FirstApply", timestamp(), "LastApply", timestamp()))

  lifecycle {
    ignore_changes = [tags.FirstApply]
  }

}

# add VMs to the domain

resource "azurerm_virtual_machine_extension" "jd" {
  count                = "${var.server_count}"
  name                 = "${var.prefix}${count.index + 1}-jd"
  virtual_machine_id   = azurerm_virtual_machine.vm1[count.index].id
  depends_on           = ["azurerm_virtual_machine.vm1"]
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"

  settings = <<SETTINGS
    {
        "Name": "winopsdba-demo7.local",
        "User": "winopsdba-demo7.local\\devadmin",
        "Restart": "true",
        "Options": "3"
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
        "Password": "${var.adminpassword}"
    }
PROTECTED_SETTINGS

  tags = merge(var.tags, map("FirstApply", timestamp(), "LastApply", timestamp()))

  lifecycle {
    ignore_changes = [tags.FirstApply]
  }

}


resource "azurerm_virtual_machine_extension" "ps1" {
  count                      = "${var.server_count}"
  name                       = "${var.prefix}-ado${count.index + 1}-localPS"
  virtual_machine_id         = "${element(azurerm_virtual_machine.vm1.*.id, count.index)}"
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.9"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.jd]

  settings = <<SETTINGS
    {
        "fileUris":["https://${var.storage_name}.blob.core.windows.net/scripts/ado-install.ps1"]
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute":"powershell -ExecutionPolicy Unrestricted -File ado-install.ps1 ${var.servicepassword} ${var.ado_token}"
    }
  PROTECTED_SETTINGS

  tags = merge(var.tags, map("FirstApply", timestamp(), "LastApply", timestamp()))

  lifecycle {
    ignore_changes = [tags.FirstApply]
  }

}

resource "azurerm_network_interface_security_group_association" "example" {
  count                     = "${var.server_count}"
  network_interface_id      = "${element(azurerm_network_interface.nic1.*.id, count.index)}"
  network_security_group_id = var.network_security_group_id
}
