#!/bin/bash

# constants for directories and files
SUDOERS_DIR="/etc/sudoers.d"
TMP_FILE="/tmp/managesudo_tmp" # temporary file for sudo rules and used for validation of syntax
LOG_FILE="/var/log/managesudo.log" # log file to store actions

# Check if the script is run as root (EUID 0 = root) 
if [[ "$EUID" -ne 0 ]]; then
	echo "Please run this script with sudo."
	exit 1
fi

# Function: Log any action with timestamp to the log file
function log_action() {

	local action="$1"
	local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"

 	# If log file doesn't exist, create and secure it 
	if [[ ! -f "$LOG_FILE" ]]; then
		sudo touch "$LOG_FILE"
		sudo chown root:devops "$LOG_FILE" # Adjust group as needed
		sudo chmod 640 "$LOG_FILE"
		echo "$timestamp Log file created." >> "$LOG_FILE"
	fi

	# Appending the action
	echo "$timestamp $action" >> "$LOG_FILE" 
	
	}

# Function: Print the current log file
function print_log() {	
	cat $LOG_FILE
}

# Function: Let user choose what kind of sudo permissions to grant
function choose_permissions() {
	local username="$1"
	echo "Choose sudo permission levels for $username"
	echo "1) Full access"
	echo "2) Command Restricted"

	while true; do
		read -rp "Enter your choice 1 or 2:" choice

		case "$choice" in
			1)
   				# Full access: all commands without password
				echo "$username ALL=(ALL) NOPASSWD:ALL" > "$TMP_FILE"
				echo "Full sudo access granted to $username"
				break
				;;
			2) 
   				# Placeholder
				echo "Not finished..."
				echo "custom access"
				break
				;;
			*) echo "Invalid choice. Enter 1 or 2"
				;;
		esac
	done
}

	# ===== if time add other access

# Function: Add user to sudoers (with safety and validation)
function add_user() {
	# Validation
	while true; do
		read -rp "Enter the username you want to add to sudoers: " username
		echo "$username"

		if [[ -z "$username" ]]; then
			echo "Username cannot be empty."

		if ! grep -q "^$username:" /etc/passwd; then
			echo "User '$username' not found in /etc/passwd."
			continue	
		fi

		else
			echo "Valid username."
			break
		fi
	done

	# Choose Permission Levels Here
	choose_permissions "$username" 

 	# No duplicate entries
	if [[ -f "$SUDOERS_DIR/managesudo_$username" ]]; then
		echo "Sudo permissions already exist for this user."
		return
	fi
 
	# Validate and move to sudoers	
	if visudo -cf "$TMP_FILE"; then
		sudo cp "$TMP_FILE" "$SUDOERS_DIR/managesudo_$username"
		sudo chmod 440 "$SUDOERS_DIR/managesudo_$username"
		echo "Sudo privileges added for $username."
	else
		echo "Invalid sudoers entry. Exiting."
	fi

	rm -f "$TMP_FILE" # clean up tmp file

	log_action "$username added by $SUDO_USER." # log the action
}

# Function: Remove sudo access for a user
function remove_user() {
	read -rp "Enter the username you want to remove from sudoers: " username

	if [[ -z "$username" ]]; then
		echo "username cannot be empty"
		return
	fi
 
	# Prevent locking out citical accounts
	if [[ "$username" == "ec2-user" || "$username" == "root" ]]; then
		echo " '$username' cannot be removed."
		return
	fi

	if [[ "$username" == "$SUDO_USER" ]]; then
		echo "You cannot remove your own sudo privileges."
		return
	fi

	#echo "Are you sure you want to delete $username?!"

	userfile="$SUDOERS_DIR/managesudo_$username"
	echo "$userfile"
	sudo ls -l "$userfile"
	if [[ -e "$userfile" ]]; then
		echo "File exists. Attempting to remove"
		sudo rm -f "$userfile"
		echo "Removed sudo access for $username."
	else
		echo "No entry found for $username."
	fi

	# usrs with ALL sudo access delete their own sudo rules
	# We need to make sure they don't lock themselves out
	
	log_action "$username removed by $SUDO_USER."
}

# Function: List all users or just those with sudo access
function list_users() {
	echo ""
	echo "=== List Users Menu ==="
	echo "1) Show all users"
	echo "2) Show all users with sudo access"
	echo "3) Back to Main Menu"
	read -rp "Choose an option 1-3" choice

	case $choice in 
		1) 
			echo "All system users:"
			awk -F: '{ print $1 }' /etc/passwd
			;;
		2)
			echo "Users with sudo access:"
			sudo ls -l "$SUDOERS_DIR"
			;;
		3)
			echo "Going back to Main Menu..."
			return
			;;
		*)
			echo "Invalid option."
			;;
	esac

	log_action "$SUDO_USER Generated list of users."
}

# Function: add or remove a user from a group
function modify_groups() {
	read -rp "Enter the username you wish to modify groups: " username

	#CHECKS

	echo "Current groups for $username:"
	groups "$username"

	# Sub menu
	echo "Select an option"
	echo "1) Add user to a group"
	echo "2) Remove user from a group"
	echo "3) Exit"
	read -rp "Choose an option 1-3: " choice

	case "$choice" in
		1) 
			read -rp "Enter a group name to add to: " groupname
			
			if [[ -z "$groupname" ]]; then
				echo "Group name cannot be empty"
				return
			fi

			#Check if group exists
			if ! getent group "$groupname"; then
				echo "The group '$groupname' does not exist."
				return
			fi

			sudo usermod -aG "$groupname" "$username"
			echo "User '$username' added to group '$groupname'"
			echo "User is in the following groups: "
			groups "$username"

			log_action "$SUDO_USER added $username to $groupname."
			;;
		2) 
			read -rp "Enter a group name to remove: " groupname

			if [[ -z "$groupname" ]]; then
				echo "Group name cannot be empty"
				return
			fi

			#Check if group exists
			if ! getent group "$groupname"; then
				echo "The group '$groupname' does not exist."
				return
			fi

			sudo gpasswd -d "$username" "$groupname"
			echo "User '$username' has been deleted from '$groupname;"
			echo "user is in the folloiwng groups: "
			groups "$username"

			log_action "$SUDO_USER removed $username from $groupname"
			;;

		3)
			echo "Exiting..."
			return
			;;

		*)
			echo "Invalid choice input number 1-3"
			return
			;;

	esac

}

function main_menu() {
	while true; do
		echo ""
		echo "Welcome $SUDO_USER"
		echo "=== sudo Manager =="
		echo "1) Add User to Sudoers"
		echo "2) Remove a user from sudoers"
		echo "3) Modify groups"
		echo "4) List current sudoers"
		echo "5) Print log file"
		echo "6) Exit"
		read -rp "Choose an option from the menu: " choice

		case $choice in
			1) add_user ;;
			2) remove_user ;;
			3) modify_groups ;;
			4) list_users ;;
			5) print_log ;;
			6) echo "Exiting"; exit 0 ;;
			*) echo "Invalid option. Please enter a number 1-5." ;;
		esac
	done
}

main_menu
