let currentPackageType = 'winget';
let editingPackageId = null;

// Load packages when the editor tab is opened
function loadPackageEditor() {
    switchPackageType('winget'); // Default to winget packages
}

// Switch between winget and chocolatey packages
async function switchPackageType(type) {
    currentPackageType = type;
    
    // Update button states
    document.querySelectorAll('.selector-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    document.querySelector(`[onclick="switchPackageType('${type}')"]`).classList.add('active');
    
    // Load packages
    await loadPackages();
}

// Load packages from the server
async function loadPackages() {
    try {
        addLogEntry(`Loading ${currentPackageType} packages...`, 'INFO');
        const response = await fetch(`/api/${currentPackageType}/packages-list`, {
            method: 'GET',
            headers: {
                'Accept': 'application/json'
            }
        });

        let data;
        try {
            data = await response.json();
        } catch (parseError) {
            throw new Error('Failed to parse server response as JSON');
        }

        if (!response.ok) {
            throw new Error(data.error || `Server returned ${response.status}: ${response.statusText}`);
        }

        if (data.success && Array.isArray(data.packages)) {
            addLogEntry(`Successfully loaded ${data.packages.length} ${currentPackageType} packages`, 'SUCCESS');
            displayPackages(data.packages);
        } else {
            throw new Error(data.error || 'Invalid package data format');
        }
    } catch (error) {
        console.error('Error loading packages:', error);
        addLogEntry(`Failed to load ${currentPackageType} packages: ${error.message}`, 'ERROR');
        displayPackages([]);
    }
}

// Display packages in the editor grid
function displayPackages(packages) {
    const grid = document.getElementById('package-editor-grid');
    grid.innerHTML = '';
    
    if (!packages || packages.length === 0) {
        grid.innerHTML = '<div class="no-packages">No packages found</div>';
        return;
    }
    
    packages.forEach(pkg => {
        const card = document.createElement('div');
        card.className = 'package-editor-card';
        card.innerHTML = `
            <div class="card-header">
                <h3 class="card-title">${pkg.app_name}</h3>
                <div class="card-actions">
                    <button class="edit-btn" onclick="editPackage('${pkg.app_id}')">Edit</button>
                    <button class="delete-btn" onclick="deletePackage('${pkg.app_id}')">Delete</button>
                </div>
            </div>
            <div class="package-id">${pkg.app_id}</div>
            <div class="card-content">${pkg.app_desc}</div>
        `;
        grid.appendChild(card);
    });
}

// Show the add/edit package modal
function showAddPackageModal(isEdit = false) {
    const modal = document.getElementById('package-modal');
    const title = document.getElementById('modal-title');
    
    title.textContent = isEdit ? 'Edit Package' : 'Add New Package';
    modal.style.display = 'block';
    
    if (!isEdit) {
        document.getElementById('package-form').reset();
        editingPackageId = null;
    }
}

// Close the modal
function closeModal() {
    document.getElementById('package-modal').style.display = 'none';
    document.getElementById('package-form').reset();
    editingPackageId = null;
}

// Edit an existing package
async function editPackage(appId) {
    try {
        const response = await fetch(`/api/${currentPackageType}/packages-list`);
        if (!response.ok) {
            throw new Error('Failed to fetch package list');
        }
        const data = await response.json();
        const package = data.packages.find(p => p.app_id === appId);
        
        if (package) {
            document.getElementById('app_id').value = package.app_id;
            document.getElementById('app_name').value = package.app_name;
            document.getElementById('app_desc').value = package.app_desc;
            editingPackageId = appId;
            showAddPackageModal(true);
        } else {
            throw new Error('Package not found');
        }
    } catch (error) {
        console.error('Error loading package for edit:', error);
        addLogEntry(`Failed to load package for editing: ${error.message}`, 'ERROR');
    }
}

// Delete a package
async function deletePackage(appId) {
    if (!confirm('Are you sure you want to delete this package?')) {
        return;
    }
    
    try {
        const response = await fetch(`/api/${currentPackageType}/packages-list`);
        if (!response.ok) {
            throw new Error('Failed to fetch package list');
        }
        const data = await response.json();
        
        if (!data.success || !data.packages) {
            throw new Error('Invalid package data');
        }
        
        const updatedPackages = data.packages.filter(p => p.app_id !== appId);
        await savePackageList(updatedPackages);
        addLogEntry(`Successfully deleted package: ${appId}`, 'SUCCESS');
        await loadPackages();
    } catch (error) {
        console.error('Error deleting package:', error);
        addLogEntry(`Failed to delete package: ${error.message}`, 'ERROR');
    }
}

// Handle form submission for adding/editing packages
async function handlePackageSubmit(event) {
    event.preventDefault();
    
    const formData = {
        app_id: document.getElementById('app_id').value,
        app_name: document.getElementById('app_name').value,
        app_desc: document.getElementById('app_desc').value
    };
    
    try {
        const response = await fetch(`/api/${currentPackageType}/packages-list`);
        if (!response.ok) {
            throw new Error('Failed to fetch package list');
        }
        const data = await response.json();
        
        if (!data.success || !data.packages) {
            throw new Error('Invalid package data');
        }
        
        let updatedPackages;
        if (editingPackageId) {
            // Edit existing package
            updatedPackages = data.packages.map(p => 
                p.app_id === editingPackageId ? formData : p
            );
        } else {
            // Add new package
            updatedPackages = [...data.packages, formData];
        }
        
        await savePackageList(updatedPackages);
        addLogEntry(`Successfully ${editingPackageId ? 'updated' : 'added'} package: ${formData.app_id}`, 'SUCCESS');
        closeModal();
        await loadPackages();
    } catch (error) {
        console.error('Error saving package:', error);
        addLogEntry(`Failed to save package: ${error.message}`, 'ERROR');
    }
}

// Save the updated package list to the server
async function savePackageList(packages) {
    try {
        addLogEntry(`Saving ${currentPackageType} package list...`, 'INFO');
        const response = await fetch('/api/save-package-list', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            },
            body: JSON.stringify({
                packageType: currentPackageType,
                packages: packages
            })
        });
        
        let data;
        try {
            data = await response.json();
        } catch (parseError) {
            throw new Error('Failed to parse server response as JSON');
        }
        
        if (!response.ok) {
            throw new Error(data.error || `Server returned ${response.status}: ${response.statusText}`);
        }
        
        if (!data.success) {
            throw new Error(data.error || 'Failed to save package list');
        }
        
        addLogEntry(`Successfully saved ${currentPackageType} package list`, 'SUCCESS');
    } catch (error) {
        const errorMessage = `Failed to save package list: ${error.message}`;
        console.error(errorMessage);
        addLogEntry(errorMessage, 'ERROR');
        throw error;
    }
} 