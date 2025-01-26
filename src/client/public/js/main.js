// Configuration constants
const CONFIG = {
    POLL_INTERVAL: 15000,        // 15 seconds between status checks
    MIN_BACKOFF: 5000,           // Minimum backoff time (5 seconds)
    MAX_BACKOFF: 30000,          // Maximum backoff time (30 seconds)
    MAX_RETRIES: 20,             // Maximum number of retry attempts
    QUEUE_CHECK_INTERVAL: 1000    // Queue processing interval (1 second)
};

// Operation queue system
const operationQueue = {
    winget: new Map(),
    choco: new Map(),
    pendingOperations: [],
    isProcessing: false,

    isOperationInProgress: function (manager, appId) {
        return this[manager].has(appId);
    },

    addOperation: function (manager, appId, operation) {
        if (this.isOperationInProgress(manager, appId)) {
            return Promise.reject(new Error('Operation already in progress'));
        }

        const promise = new Promise((resolve, reject) => {
            this.pendingOperations.push({
                manager,
                appId,
                operation,
                resolve,
                reject,
                retryCount: 0,
                nextRetryDelay: CONFIG.MIN_BACKOFF,
                isStopped: false
            });
        });

        this[manager].set(appId, promise);
        this.processQueue();
        return promise;
    },

    stopOperation: function (manager, appId) {
        const pendingOp = this.pendingOperations.find(op =>
            op.manager === manager && op.appId === appId
        );

        if (pendingOp) {
            pendingOp.isStopped = true;
            this.pendingOperations = this.pendingOperations.filter(op =>
                !(op.manager === manager && op.appId === appId)
            );
            this[manager].delete(appId);
            pendingOp.reject(new Error('Operation stopped by user'));
            return true;
        }
        return false;
    },

    processQueue: async function () {
        if (this.isProcessing || this.pendingOperations.length === 0) return;

        this.isProcessing = true;
        const op = this.pendingOperations.shift();

        try {
            if (!op.isStopped) {
                const result = await op.operation();
                this[op.manager].delete(op.appId);
                op.resolve(result);
            }
        } catch (error) {
            if (!op.isStopped && op.retryCount < CONFIG.MAX_RETRIES) {
                op.retryCount++;
                op.nextRetryDelay = Math.min(
                    op.nextRetryDelay * 2,
                    CONFIG.MAX_BACKOFF
                );
                setTimeout(() => {
                    this.pendingOperations.push(op);
                }, op.nextRetryDelay);
            } else {
                this[op.manager].delete(op.appId);
                op.reject(error);
            }
        }

        this.isProcessing = false;
        setTimeout(() => this.processQueue(), CONFIG.QUEUE_CHECK_INTERVAL);
    }
};

// Global state to track package initialization
let hasInitializedWingetPackages = false;
let hasInitializedChocoPackages = false;

/**
 * Tab Management
 * Handles switching between different tabs and initializes package loading
 * @param {string} tabName - Name of the tab to open
 */
function openTab(tabName) {
    // Hide all tab contents
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    
    // Remove active class from all tabs
    document.querySelectorAll('.tab').forEach(tab => {
        tab.classList.remove('active');
    });
    
    // Show the selected tab content
    document.getElementById(tabName).classList.add('active');
    
    // Add active class to the clicked tab
    document.querySelector(`[onclick="openTab('${tabName}')"]`).classList.add('active');
    
    addLogEntry(`Switching to ${tabName} tab`, 'INFO');
    
    // Initialize specific tab content if needed
    if (tabName === 'winget-status' && !hasInitializedWingetPackages) {
        addLogEntry('First time opening Winget Status tab - initializing package list', 'INFO');
        loadWingetPackages();
        hasInitializedWingetPackages = true;
    } else if (tabName === 'choco-status' && !hasInitializedChocoPackages) {
        addLogEntry('First time opening Chocolatey Status tab - initializing package list', 'INFO');
        loadChocoPackages();
        hasInitializedChocoPackages = true;
    } else if (tabName === 'package-editor') {
        loadPackageEditor();
    }
}

/**
 * Log Entry Management
 * Adds a new log entry to the log container with timestamp and styling
 * @param {string} message - The log message to display
 * @param {string} type - The type of log (INFO, DEBUG, SUCCESS, WARNING, ERROR, REQUEST, RESPONSE)
 */
function addLogEntry(message, type) {
    const logContainer = document.getElementById('logContainer');
    const logEntry = document.createElement('div');
    logEntry.className = `log-entry ${type.toLowerCase()}`;

    // Add timestamp
    const timestamp = new Date().toLocaleTimeString();
    logEntry.textContent = `[${timestamp}] ${message}`;

    logContainer.appendChild(logEntry);
    logContainer.scrollTop = logContainer.scrollHeight;

    // Send log to server for persistence
    fetch('http://localhost:9000/api/log', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            message: message,
            type: type,
            source: 'GUI'
        })
    }).catch(err => console.error('Failed to send log to server:', err));
}

/**
 * Log Management Functions
 * Handle copying, downloading, and clearing of logs
 */
function copyLogs() {
    addLogEntry('Copying logs to clipboard', 'INFO');
    const logContainer = document.getElementById('logContainer');
    const logText = Array.from(logContainer.children)
        .map(entry => entry.textContent)
        .join('\n');

    navigator.clipboard.writeText(logText).then(() => {
        addLogEntry('Logs copied successfully', 'SUCCESS');
    }).catch(err => {
        addLogEntry(`Failed to copy logs: ${err.message}`, 'ERROR');
    });
}

function downloadLogs() {
    addLogEntry('Preparing logs for download', 'INFO');
    const logContainer = document.getElementById('logContainer');
    const logText = Array.from(logContainer.children)
        .map(entry => entry.textContent)
        .join('\n');

    const blob = new Blob([logText], { type: 'text/plain' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');

    const timestamp = new Date().toISOString().slice(0, 19).replace(/[:]/g, '-');
    a.href = url;
    a.download = `logs_${timestamp}.txt`;
    document.body.appendChild(a);
    a.click();

    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
    addLogEntry('Logs downloaded successfully', 'SUCCESS');
}

function clearLogs() {
    if (confirm('Are you sure you want to clear all logs?')) {
        const logContainer = document.getElementById('logContainer');
        logContainer.innerHTML = '';
        addLogEntry('Log history cleared', 'INFO');
    }
}

// Initialize UI elements
const wingetBtn = document.getElementById('checkWinget');
const chocoBtn = document.getElementById('checkChoco');
const chocoToggle = document.getElementById('chocoToggle');

/**
 * Winget Version Check
 * Queries the server for Winget version and updates UI accordingly
 */
async function checkWinget() {
    const result = document.getElementById('wingetResult');
    wingetBtn.disabled = true;
    addLogEntry('Checking Winget version...', 'INFO');

    try {
        const response = await fetch('http://localhost:9000/api/winget-version');
        const data = await response.json();

        if (data.version && !data.version.includes('Error')) {
            result.textContent = `Version: ${data.version}`;
            result.className = 'result success';
            addLogEntry(`Winget version check successful: ${data.version}`, 'SUCCESS');
        } else {
            result.textContent = 'Winget not installed';
            result.className = 'result error';
            addLogEntry('Winget not installed', 'ERROR');
        }
    } catch (error) {
        result.textContent = 'Error checking version';
        result.className = 'result error';
        addLogEntry(`Error checking Winget version: ${error.message}`, 'ERROR');
    }
    wingetBtn.disabled = false;
}

/**
 * Chocolatey Version Check
 * Queries the server for Chocolatey version and updates UI accordingly
 */
async function checkChoco() {
    const result = document.getElementById('chocoResult');
    chocoBtn.disabled = true;
    addLogEntry('Checking Chocolatey version...', 'INFO');

    try {
        const response = await fetch('http://localhost:9000/api/choco-version');
        const data = await response.json();

        if (data.version.installed) {
            result.textContent = `Version: ${data.version.version}`;
            result.className = 'result success';
            chocoToggle.checked = true;
            addLogEntry(`Chocolatey version check successful: ${data.version.version}`, 'SUCCESS');
        } else {
            result.textContent = 'Chocolatey is not installed';
            result.className = 'result error';
            chocoToggle.checked = false;
            addLogEntry('Chocolatey is not installed', 'WARNING');
        }
    } catch (error) {
        result.textContent = 'Error checking version';
        result.className = 'result error';
        addLogEntry(`Error checking Chocolatey version: ${error.message}`, 'ERROR');
    }
    chocoBtn.disabled = false;
}

/**
 * Chocolatey Installation Toggle Handler
 * Manages installation/uninstallation of Chocolatey based on toggle state
 */
chocoToggle.addEventListener('change', async () => {
    const result = document.getElementById('chocoResult');
    const endpoint = chocoToggle.checked ? 'install' : 'uninstall';
    const action = chocoToggle.checked ? 'Installing' : 'Uninstalling';

    result.textContent = `${action}...`;
    result.className = 'result';
    addLogEntry(`${action} Chocolatey...`, 'INFO');

    try {
        // Perform installation/uninstallation
        const response = await fetch(`http://localhost:9000/api/choco-${endpoint}`);
        const data = await response.json();

        // Wait for operation to complete
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Verify installation status
        const verifyResponse = await fetch('http://localhost:9000/api/choco-version');
        const verifyData = await verifyResponse.json();

        const isInstalled = verifyData.version.installed;
        const shouldBeInstalled = endpoint === 'install';

        if (isInstalled === shouldBeInstalled) {
            await checkChoco(); // Updates UI and logs success
        } else {
            result.textContent = `${endpoint} failed`;
            result.className = 'result error';
            chocoToggle.checked = !chocoToggle.checked;
            addLogEntry(`Chocolatey ${endpoint} failed - verification failed`, 'ERROR');
        }
    } catch (error) {
        result.textContent = `${endpoint} failed`;
        result.className = 'result error';
        chocoToggle.checked = !chocoToggle.checked;
        addLogEntry(`Error during Chocolatey ${endpoint}: ${error.message}`, 'ERROR');
    }
});

// Event Listeners for version check buttons
wingetBtn.addEventListener('click', checkWinget);
chocoBtn.addEventListener('click', checkChoco);

/**
 * Package Management Functions
 * Handle loading, displaying, and managing package status
 */

/**
 * Loads and displays all Winget packages
 * Creates cards for each package with status, version, and controls
 */
async function loadWingetPackages() {
    const packageGrid = document.getElementById('winget-package-grid');
    packageGrid.innerHTML = 'Loading packages...';
    addLogEntry('Loading Winget package list...', 'INFO');

    try {
        // Check for cached package data
        const cachedData = sessionStorage.getItem('wingetPackageData');
        if (cachedData) {
            addLogEntry('Using cached Winget package data', 'INFO');
            displayWingetPackages(JSON.parse(cachedData));
            return;
        }

        // Fetch package list from server
        const response = await fetch('http://localhost:9000/api/winget/packages-list');
        const data = await response.json();

        if (data.success) {
            sessionStorage.setItem('wingetPackageData', JSON.stringify(data));
            addLogEntry(`Successfully loaded ${data.packages.length} Winget packages`, 'SUCCESS');
            displayWingetPackages(data);
        } else {
            packageGrid.innerHTML = 'Error loading Winget packages list';
            addLogEntry('Failed to load Winget packages list', 'ERROR');
        }
    } catch (error) {
        packageGrid.innerHTML = 'Error loading Winget packages list';
        addLogEntry(`Error loading Winget packages: ${error.message}`, 'ERROR');
    }
}

/**
 * Displays Winget packages and their status
 * @param {Object} data - Package data to display
 */
async function displayWingetPackages(data) {
    const packageGrid = document.getElementById('winget-package-grid');
    packageGrid.innerHTML = '';
    addLogEntry('Rendering Winget package cards...', 'DEBUG');

    for (const pkg of data.packages) {
        const card = document.createElement('div');
        card.className = 'package-card';
        card.setAttribute('data-app-id', pkg.app_id);  // Add data-app-id attribute

        card.innerHTML = `
            <h4>${pkg.app_name}</h4>
            <div class="package-desc">${pkg.app_desc}</div>
            <div class="package-status">
                <div class="status-info">
                    <span class="status-badge">Checking...</span>
                    <span class="version"></span>
                </div>
                <div class="package-controls">
                    <button class="refresh-btn" onclick="refreshWingetPackage('${pkg.app_id}', this)">
                        <span class="refresh-icon">↻</span>
                    </button>
                    <button class="stop-btn" onclick="stopPackageOperation('winget', '${pkg.app_id}', this)" style="display: none;">
                        <span class="stop-icon">⬛</span>
                    </button>
                    <label class="toggle package-toggle">
                        <input type="checkbox" data-app-id="${pkg.app_id}">
                        <span class="slider"></span>
                    </label>
                </div>
            </div>
            <div class="package-progress">
                <div class="progress-container">
                    <div class="progress-bar">
                        <div class="progress-bar-fill"></div>
                    </div>
                    <div class="progress-text"></div>
                </div>
            </div>
        `;

        packageGrid.appendChild(card);

        const toggle = card.querySelector('input[type="checkbox"]');
        toggle.addEventListener('change', () => handleWingetPackageToggle(pkg.app_id, toggle));
    }

    // Check for cached status data
    const cachedStatus = sessionStorage.getItem('wingetPackageStatus');
    if (cachedStatus) {
        addLogEntry('Using cached Winget package status data', 'INFO');
        updateWingetPackageStatusFromCache(JSON.parse(cachedStatus));
    } else {
        // Only perform bulk status check once
        await performWingetBulkStatusCheck();
    }
}

/**
 * Updates Winget package status from cached data
 * @param {Object} statusData - Cached status data
 */
function updateWingetPackageStatusFromCache(statusData) {
    addLogEntry('Updating Winget package status from cache...', 'DEBUG');
    const packageCards = document.querySelectorAll('#winget-package-grid .package-card');

    packageCards.forEach(card => {
        const appId = card.querySelector('input[type="checkbox"]').dataset.appId;
        const status = statusData[appId];

        if (status) {
            const statusBadge = card.querySelector('.status-badge');
            const versionSpan = card.querySelector('.version');
            const toggle = card.querySelector('input[type="checkbox"]');

            if (status.installed) {
                statusBadge.textContent = 'Installed';
                statusBadge.className = 'status-badge installed';
                versionSpan.textContent = status.version || '';
                toggle.checked = true;
                addLogEntry(`Winget package ${appId} is installed (version ${status.version || 'unknown'})`, 'SUCCESS');
            } else {
                statusBadge.textContent = 'Not Installed';
                statusBadge.className = 'status-badge not-installed';
                versionSpan.textContent = '';
                toggle.checked = false;
                addLogEntry(`Winget package ${appId} is not installed`, 'INFO');
            }
        }
    });
    addLogEntry('Winget package status updated from cache', 'SUCCESS');
}

/**
 * Progress Bar Management Functions
 */
function showProgress(container, text = '') {
    const progressContainer = container.querySelector('.progress-container');
    const progressText = container.querySelector('.progress-text');
    const progressBarFill = container.querySelector('.progress-bar-fill');

    progressContainer.style.display = 'block';
    progressText.textContent = text;
    progressBarFill.style.width = '0%';
    progressBarFill.classList.remove('indeterminate');
}

function updateProgress(container, progress, text = '') {
    const progressBarFill = container.querySelector('.progress-bar-fill');
    const progressText = container.querySelector('.progress-text');

    if (progress === -1) {
        progressBarFill.classList.add('indeterminate');
    } else {
        progressBarFill.classList.remove('indeterminate');
        progressBarFill.style.width = `${progress}%`;
    }

    if (text) {
        progressText.textContent = text;
    }
}

function hideProgress(container) {
    const progressContainer = container.querySelector('.progress-container');
    progressContainer.style.display = 'none';
}

/**
 * Updated Winget Bulk Status Check
 */
async function performWingetBulkStatusCheck(forceRefresh = false) {
    const packageCards = document.querySelectorAll('#winget-package-grid .package-card');
    const bulkProgressContainer = document.querySelector('#winget-status .bulk-progress');
    const bulkRefreshBtn = document.querySelector('#winget-status .bulk-refresh-btn');
    const totalPackages = packageCards.length;
    let completedPackages = 0;

    showProgress(bulkProgressContainer, 'Starting bulk check...');
    bulkRefreshBtn.disabled = true;

    packageCards.forEach(card => {
        const statusBadge = card.querySelector('.status-badge');
        const toggle = card.querySelector('input[type="checkbox"]');
        if (statusBadge) {
            statusBadge.textContent = 'Checking...';
            statusBadge.className = 'status-badge pending';
        }
        if (toggle) {
            toggle.disabled = true;
        }
    });

    try {
        addLogEntry('Starting Winget bulk status check...', 'DEBUG');

        // Create a status cache object
        const statusCache = {};

        // Function to update a single package's status
        function updatePackageStatus(result) {
            completedPackages++;
            const progress = (completedPackages / totalPackages) * 100;

            const card = document.querySelector(`#winget-package-grid .package-card[data-app-id="${result.appId}"]`);
            if (card) {
                const statusBadge = card.querySelector('.status-badge');
                const versionSpan = card.querySelector('.version');
                const toggle = card.querySelector('input[type="checkbox"]');

                if (result.status.installed) {
                    statusBadge.textContent = 'Installed';
                    statusBadge.className = 'status-badge installed';
                    versionSpan.textContent = result.status.version || '';
                    toggle.checked = true;
                    addLogEntry(`Winget package ${result.appId} is installed (version ${result.status.version || 'unknown'})`, 'SUCCESS');
                } else {
                    statusBadge.textContent = 'Not Installed';
                    statusBadge.className = 'status-badge not-installed';
                    versionSpan.textContent = '';
                    toggle.checked = false;
                    addLogEntry(`Winget package ${result.appId} is not installed`, 'INFO');
                }
                toggle.disabled = false;

                // Cache the status
                statusCache[result.appId] = result.status;
            }

            // Update progress bar
            if (completedPackages >= totalPackages) {
                // All packages processed - show completion
                updateProgress(bulkProgressContainer, 100, 'Status check complete');
                setTimeout(() => {
                    hideProgress(bulkProgressContainer);
                    bulkRefreshBtn.disabled = false;
                }, 1000);

                // Store the status cache in sessionStorage
                sessionStorage.setItem('wingetPackageStatus', JSON.stringify(statusCache));
                addLogEntry('Winget bulk status check completed successfully', 'SUCCESS');
            } else {
                // Still processing - show current package
                updateProgress(bulkProgressContainer, progress, `Checking packages (${completedPackages}/${totalPackages})...`);
            }
        }

        // Process each package one by one
        for (const card of packageCards) {
            const appId = card.getAttribute('data-app-id');
            try {
                const response = await fetch('http://localhost:9000/api/winget/bulk-status', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ appId, refresh: forceRefresh })
                });

                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }

                const data = await response.json();
                if (!data.success) {
                    throw new Error(data.error || 'Failed to get status');
                }

                // Update the UI for this package
                if (data.results && data.results.length > 0) {
                    updatePackageStatus(data.results[0]);
                }
            } catch (error) {
                addLogEntry(`Error checking status for ${appId}: ${error.message}`, 'ERROR');
                const statusBadge = card.querySelector('.status-badge');
                const toggle = card.querySelector('input[type="checkbox"]');
                statusBadge.textContent = 'Error';
                statusBadge.className = 'status-badge not-installed';
                toggle.disabled = false;

                // Update progress even for failed checks
                completedPackages++;
                const progress = (completedPackages / totalPackages) * 100;
                updateProgress(bulkProgressContainer, progress, `Error checking ${appId}`);

                // Check if this was the last package
                if (completedPackages >= totalPackages) {
                    setTimeout(() => {
                        hideProgress(bulkProgressContainer);
                        bulkRefreshBtn.disabled = false;
                    }, 1000);
                }
            }
        }

    } catch (error) {
        updateProgress(bulkProgressContainer, 100, 'Error during bulk check');
        setTimeout(() => {
            hideProgress(bulkProgressContainer);
            bulkRefreshBtn.disabled = false;
        }, 2000);

        packageCards.forEach(card => {
            const statusBadge = card.querySelector('.status-badge');
            const toggle = card.querySelector('input[type="checkbox"]');
            statusBadge.textContent = 'Error';
            statusBadge.className = 'status-badge not-installed';
            toggle.disabled = false;
        });

        addLogEntry(`Error during Winget bulk status check: ${error.message}`, 'ERROR');
    }
}

/**
 * Forces a bulk status check for all Winget packages
 */
async function forceWingetBulkStatusCheck() {
    const bulkRefreshBtn = document.querySelector('#winget-status .bulk-refresh-btn');
    const packageCards = document.querySelectorAll('#winget-package-grid .package-card');

    addLogEntry('Starting forced Winget bulk status check...', 'INFO');
    bulkRefreshBtn.disabled = true;

    try {
        // Clear the cached data
        sessionStorage.removeItem('wingetPackageData');
        sessionStorage.removeItem('wingetPackageStatus');
        
        // Reload the package list
        await loadWingetPackages();
        addLogEntry('Forced Winget bulk status check completed successfully', 'SUCCESS');
    } catch (error) {
        addLogEntry(`Error during forced Winget bulk status check: ${error.message}`, 'ERROR');

        packageCards.forEach(card => {
            const statusBadge = card.querySelector('.status-badge');
            statusBadge.textContent = 'Error';
            statusBadge.className = 'status-badge not-installed';
        });
    } finally {
        bulkRefreshBtn.disabled = false;
    }
}

/**
 * Updated Winget Package Toggle Handler
 */
async function handleWingetPackageToggle(appId, toggle) {
    const card = toggle.closest('.package-card');
    const progressContainer = card.querySelector('.package-progress');
    const statusBadge = card.querySelector('.status-badge');
    const action = toggle.checked ? 'install' : 'uninstall';

    showProgress(progressContainer, `Starting ${action}...`);
    updateProgress(progressContainer, 5, `Preparing to ${action}...`);
    statusBadge.textContent = toggle.checked ? 'Installing...' : 'Uninstalling...';
    toggle.disabled = true;

    try {
        const response = await fetch(`http://localhost:9000/api/winget/${action}-package`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ appId })
        });

        // Set up SSE for progress updates
        const eventSource = new EventSource(`http://localhost:9000/api/winget/operation-progress/${appId}`);

        eventSource.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.progress) {
                updateProgress(progressContainer, data.progress, data.status || `${action.charAt(0).toUpperCase() + action.slice(1)}ing...`);
            }
        };

        eventSource.onerror = () => {
            eventSource.close();
        };

        const data = await response.json();
        eventSource.close();

        if (!data.success) {
            throw new Error(data.error || `Failed to ${action} package`);
        }

        // Update progress based on installation/uninstallation status
        if (data.installed !== undefined) {
            updateProgress(progressContainer, 100, 'Operation complete!');

            // Update status badge and toggle
            statusBadge.textContent = data.installed ? 'Installed' : 'Not Installed';
            statusBadge.className = `status-badge ${data.installed ? 'installed' : 'not-installed'}`;
            toggle.checked = data.installed;

            setTimeout(() => {
                hideProgress(progressContainer);
                toggle.disabled = false;
            }, 1000);
        } else {
            throw new Error('Invalid response from server');
        }

    } catch (error) {
        updateProgress(progressContainer, 100, 'Error!');
        statusBadge.textContent = 'Error';
        statusBadge.className = 'status-badge not-installed';

        setTimeout(() => {
            hideProgress(progressContainer);
            toggle.checked = !toggle.checked;
            toggle.disabled = false;
        }, 2000);

        addLogEntry(`Error during ${action}: ${error.message}`, 'ERROR');
    }
}

/**
 * Refreshes the status of a single Winget package
 * @param {string} appId - The package identifier
 * @param {HTMLElement} button - The refresh button element
 */
async function refreshWingetPackage(appId, button) {
    const card = button.closest('.package-card');
    const statusBadge = card.querySelector('.status-badge');
    const refreshIcon = button.querySelector('.refresh-icon');

    addLogEntry(`Refreshing status for Winget package ${appId}...`, 'INFO');
    button.disabled = true;
    statusBadge.textContent = 'Checking...';
    refreshIcon.style.transform = 'rotate(360deg)';

    try {
        const response = await fetch('http://localhost:9000/api/winget/single-package-status', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ appId, refresh: true })
        });

        const data = await response.json();
        const versionSpan = card.querySelector('.version');
        const toggle = card.querySelector('input[type="checkbox"]');

        if (data.status.installed) {
            statusBadge.textContent = 'Installed';
            statusBadge.className = 'status-badge installed';
            versionSpan.textContent = data.status.version || '';
            toggle.checked = true;
            addLogEntry(`Winget package ${appId} is installed (version ${data.status.version || 'unknown'})`, 'SUCCESS');
        } else {
            statusBadge.textContent = 'Not Installed';
            statusBadge.className = 'status-badge not-installed';
            versionSpan.textContent = '';
            toggle.checked = false;
            addLogEntry(`Winget package ${appId} is not installed`, 'INFO');
        }
    } catch (error) {
        statusBadge.textContent = 'Error';
        statusBadge.className = 'status-badge not-installed';
        addLogEntry(`Error refreshing Winget package status for ${appId}: ${error.message}`, 'ERROR');
    } finally {
        button.disabled = false;
        refreshIcon.style.transform = 'rotate(0deg)';
    }
}

/**
 * Stops a package operation and updates UI
 * @param {string} manager - The package manager (winget/choco)
 * @param {string} appId - The package identifier
 * @param {HTMLElement} button - The stop button element
 */
async function stopPackageOperation(manager, appId, button) {
    const card = button.closest('.package-card');
    const statusBadge = card.querySelector('.status-badge');
    const toggle = card.querySelector('input[type="checkbox"]');
    const stopBtn = card.querySelector('.stop-btn');

    addLogEntry(`Stopping ${manager} operation for package ${appId}...`, 'INFO');

    if (operationQueue.stopOperation(manager, appId)) {
        statusBadge.textContent = 'Operation Stopped';
        toggle.checked = !toggle.checked;
        toggle.disabled = false;
        stopBtn.style.display = 'none';
        addLogEntry(`Successfully stopped ${manager} operation for package ${appId}`, 'SUCCESS');
    }
}

/**
 * Loads and displays all Chocolatey packages
 * Creates cards for each package with status, version, and controls
 */
async function loadChocoPackages() {
    const packageGrid = document.getElementById('choco-package-grid');
    packageGrid.innerHTML = 'Loading packages...';
    addLogEntry('Loading Chocolatey package list...', 'INFO');

    try {
        // Check for cached package data
        const cachedData = sessionStorage.getItem('chocoPackageData');
        if (cachedData) {
            addLogEntry('Using cached Chocolatey package data', 'INFO');
            displayChocoPackages(JSON.parse(cachedData));
            return;
        }

        // Fetch package list from server
        const response = await fetch('http://localhost:9000/api/choco/packages-list');
        const data = await response.json();

        if (data.success) {
            sessionStorage.setItem('chocoPackageData', JSON.stringify(data));
            addLogEntry(`Successfully loaded ${data.packages.length} Chocolatey packages`, 'SUCCESS');
            displayChocoPackages(data);
        } else {
            packageGrid.innerHTML = 'Error loading Chocolatey packages list';
            addLogEntry('Failed to load Chocolatey packages list', 'ERROR');
        }
    } catch (error) {
        packageGrid.innerHTML = 'Error loading Chocolatey packages list';
        addLogEntry(`Error loading Chocolatey packages: ${error.message}`, 'ERROR');
    }
}

/**
 * Displays Chocolatey packages and their status
 * @param {Object} data - Package data to display
 */
async function displayChocoPackages(data) {
    const packageGrid = document.getElementById('choco-package-grid');
    packageGrid.innerHTML = '';
    addLogEntry('Rendering Chocolatey package cards...', 'DEBUG');

    for (const pkg of data.packages) {
        const card = document.createElement('div');
        card.className = 'package-card';

        card.innerHTML = `
            <h4>${pkg.app_name}</h4>
            <div class="package-desc">${pkg.app_desc}</div>
            <div class="package-status">
                <div class="status-info">
                    <span class="status-badge">Checking...</span>
                    <span class="version"></span>
                </div>
                <div class="package-controls">
                    <button class="refresh-btn" onclick="refreshChocoPackage('${pkg.app_id}', this)">
                        <span class="refresh-icon">↻</span>
                    </button>
                    <button class="stop-btn" onclick="stopPackageOperation('choco', '${pkg.app_id}', this)" style="display: none;">
                        <span class="stop-icon">⬛</span>
                    </button>
                    <label class="toggle package-toggle">
                        <input type="checkbox" data-app-id="${pkg.app_id}">
                        <span class="slider"></span>
                    </label>
                </div>
            </div>
            <div class="package-progress">
                <div class="progress-container">
                    <div class="progress-bar">
                        <div class="progress-bar-fill"></div>
                    </div>
                    <div class="progress-text"></div>
                </div>
            </div>
        `;

        packageGrid.appendChild(card);

        const toggle = card.querySelector('input[type="checkbox"]');
        toggle.addEventListener('change', () => handleChocoPackageToggle(pkg.app_id, toggle));
    }

    // Check for cached status data
    const cachedStatus = sessionStorage.getItem('chocoPackageStatus');
    if (cachedStatus) {
        addLogEntry('Using cached Chocolatey package status data', 'INFO');
        updateChocoPackageStatusFromCache(JSON.parse(cachedStatus));
    } else {
        addLogEntry('Performing initial Chocolatey bulk status check...', 'INFO');
        await performInitialChocoBulkCheck();
    }
}

/**
 * Updates Chocolatey package status from cached data
 * @param {Object} statusData - Cached status data
 */
function updateChocoPackageStatusFromCache(statusData) {
    addLogEntry('Updating Chocolatey package status from cache...', 'DEBUG');
    const packageCards = document.querySelectorAll('#choco-package-grid .package-card');

    packageCards.forEach(card => {
        const appId = card.querySelector('input[type="checkbox"]').dataset.appId;
        const status = statusData[appId];

        if (status) {
            const statusBadge = card.querySelector('.status-badge');
            const versionSpan = card.querySelector('.version');
            const toggle = card.querySelector('input[type="checkbox"]');

            if (status.installed) {
                statusBadge.textContent = 'Installed';
                statusBadge.className = 'status-badge installed';
                versionSpan.textContent = status.version || '';
                toggle.checked = true;
                addLogEntry(`Chocolatey package ${appId} is installed (version ${status.version || 'unknown'})`, 'SUCCESS');
            } else {
                statusBadge.textContent = 'Not Installed';
                statusBadge.className = 'status-badge not-installed';
                versionSpan.textContent = '';
                toggle.checked = false;
                addLogEntry(`Chocolatey package ${appId} is not installed`, 'INFO');
            }
        }
    });
    addLogEntry('Chocolatey package status updated from cache', 'SUCCESS');
}

/**
 * Updated Chocolatey Bulk Status Check
 */
async function performInitialChocoBulkCheck(forceRefresh = false) {
    const packageCards = document.querySelectorAll('#choco-package-grid .package-card');
    const bulkProgressContainer = document.querySelector('#choco-status .bulk-progress');
    const bulkRefreshBtn = document.querySelector('#choco-status .bulk-refresh-btn');
    const statusCache = {};

    showProgress(bulkProgressContainer, 'Starting bulk check...');
    bulkRefreshBtn.disabled = true;

    try {
        const packageIds = Array.from(packageCards).map(card =>
            card.querySelector('input[type="checkbox"]').dataset.appId
        );

        addLogEntry(`Checking status for ${packageIds.length} Chocolatey packages...`, 'INFO');

        let completedChecks = 0;
        const totalPackages = packageIds.length;

        // Create an array of promises for all package checks
        const checkPromises = packageIds.map(async appId => {
            const card = Array.from(packageCards).find(card =>
                card.querySelector('input[type="checkbox"]').dataset.appId === appId
            );

            addLogEntry(`Checking status for Chocolatey package ${appId}...`, 'DEBUG');

            try {
                const response = await fetch('http://localhost:9000/api/choco/bulk-package-status', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ appId, refresh: forceRefresh })
                });

                const data = await response.json();
                statusCache[appId] = data.status;

                completedChecks++;
                const progress = (completedChecks / totalPackages) * 100;
                updateProgress(bulkProgressContainer, progress, `Checking packages (${completedChecks}/${totalPackages})...`);

                const statusBadge = card.querySelector('.status-badge');
                const versionSpan = card.querySelector('.version');
                const toggle = card.querySelector('input[type="checkbox"]');

                if (data.status && data.status.installed) {
                    statusBadge.textContent = 'Installed';
                    statusBadge.className = 'status-badge installed';
                    versionSpan.textContent = data.status.version || '';
                    toggle.checked = true;
                    addLogEntry(`Chocolatey package ${appId} is installed (version ${data.status.version || 'unknown'})`, 'SUCCESS');
                } else {
                    statusBadge.textContent = 'Not Installed';
                    statusBadge.className = 'status-badge not-installed';
                    versionSpan.textContent = '';
                    toggle.checked = false;
                    addLogEntry(`Chocolatey package ${appId} is not installed`, 'INFO');
                }
                return { appId, success: true };
            } catch (error) {
                completedChecks++;
                const progress = (completedChecks / totalPackages) * 100;
                updateProgress(bulkProgressContainer, progress, `Checking packages (${completedChecks}/${totalPackages})...`);

                const statusBadge = card.querySelector('.status-badge');
                statusBadge.textContent = 'Error';
                statusBadge.className = 'status-badge not-installed';
                addLogEntry(`Error checking Chocolatey package ${appId}: ${error.message}`, 'ERROR');
                return { appId, success: false, error };
            }
        });

        // Wait for all checks to complete
        const results = await Promise.allSettled(checkPromises);
        const failures = results.filter(r => r.status === 'rejected' || (r.status === 'fulfilled' && !r.value.success));

        // Update progress bar to completion
        updateProgress(bulkProgressContainer, 100, 'Status check complete');
        setTimeout(() => {
            hideProgress(bulkProgressContainer);
            bulkRefreshBtn.disabled = false;
        }, 1000);

        if (failures.length > 0) {
            addLogEntry(`${failures.length} Chocolatey package checks failed`, 'WARNING');
        } else {
            sessionStorage.setItem('chocoPackageStatus', JSON.stringify(statusCache));
            addLogEntry('Initial Chocolatey bulk status check completed successfully', 'SUCCESS');
        }

    } catch (error) {
        addLogEntry(`Error during Chocolatey bulk status check: ${error.message}`, 'ERROR');

        updateProgress(bulkProgressContainer, 100, 'Error during bulk check');
        setTimeout(() => {
            hideProgress(bulkProgressContainer);
            bulkRefreshBtn.disabled = false;
        }, 2000);

        packageCards.forEach(card => {
            const statusBadge = card.querySelector('.status-badge');
            statusBadge.textContent = 'Error';
            statusBadge.className = 'status-badge not-installed';
        });
    }
}

/**
 * Updated Chocolatey Package Toggle Handler
 */
async function handleChocoPackageToggle(appId, toggle) {
    const card = toggle.closest('.package-card');
    const statusBadge = card.querySelector('.status-badge');
    const versionSpan = card.querySelector('.version');
    const stopBtn = card.querySelector('.stop-btn');
    const progressContainer = card.querySelector('.package-progress');
    const action = toggle.checked ? 'install' : 'uninstall';
    const originalState = !toggle.checked;

    addLogEntry(`Starting ${action} for Chocolatey package ${appId}...`, 'INFO');
    statusBadge.textContent = toggle.checked ? 'Installing...' : 'Uninstalling...';
    toggle.disabled = true;
    stopBtn.style.display = 'flex';
    showProgress(progressContainer, `Starting ${action}...`);
    updateProgress(progressContainer, 5, `Preparing to ${action}...`);

    try {
        const response = await fetch(`http://localhost:9000/api/choco/${action}-package`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ appId })
        });

        const data = await response.json();

        if (!data.success) {
            throw new Error(data.error || `Failed to ${action} package`);
        }

        // Update progress to show completion
        updateProgress(progressContainer, 100, 'Operation complete!');

        // Get the latest status after installation
        const statusResponse = await fetch('http://localhost:9000/api/choco/single-package-status', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ appId, refresh: true })
        });

        const statusData = await statusResponse.json();

        // Update UI based on the latest status
        if (statusData.status.installed) {
            statusBadge.textContent = 'Installed';
            statusBadge.className = 'status-badge installed';
            versionSpan.textContent = statusData.status.version || '';
            toggle.checked = true;
            addLogEntry(`Successfully installed Chocolatey package ${appId} (version ${statusData.status.version || 'unknown'})`, 'SUCCESS');
        } else {
            statusBadge.textContent = 'Not Installed';
            statusBadge.className = 'status-badge not-installed';
            versionSpan.textContent = '';
            toggle.checked = false;
            addLogEntry(`Successfully uninstalled Chocolatey package ${appId}`, 'SUCCESS');
        }

        setTimeout(() => {
            hideProgress(progressContainer);
            stopBtn.style.display = 'none';
            toggle.disabled = false;
        }, 1000);

    } catch (error) {
        updateProgress(progressContainer, 100, 'Error!');
        statusBadge.textContent = 'Error';
        statusBadge.className = 'status-badge not-installed';
        versionSpan.textContent = '';

        setTimeout(() => {
            hideProgress(progressContainer);
            stopBtn.style.display = 'none';
            toggle.checked = originalState;
            toggle.disabled = false;
        }, 2000);

        addLogEntry(`Error during ${action}: ${error.message}`, 'ERROR');
    }
}

/**
 * Refreshes the status of a single Chocolatey package
 * @param {string} appId - The package identifier
 * @param {HTMLElement} button - The refresh button element
 */
async function refreshChocoPackage(appId, button) {
    const card = button.closest('.package-card');
    const statusBadge = card.querySelector('.status-badge');
    const refreshIcon = button.querySelector('.refresh-icon');

    addLogEntry(`Refreshing status for Chocolatey package ${appId}...`, 'INFO');
    button.disabled = true;
    statusBadge.textContent = 'Checking...';
    refreshIcon.style.transform = 'rotate(360deg)';

    try {
        const response = await fetch('http://localhost:9000/api/choco/single-package-status', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ appId, refresh: true })
        });

        const data = await response.json();
        const versionSpan = card.querySelector('.version');
        const toggle = card.querySelector('input[type="checkbox"]');

        if (data.status.installed) {
            statusBadge.textContent = 'Installed';
            statusBadge.className = 'status-badge installed';
            versionSpan.textContent = data.status.version || '';
            toggle.checked = true;
            addLogEntry(`Chocolatey package ${appId} is installed (version ${data.status.version || 'unknown'})`, 'SUCCESS');
        } else {
            statusBadge.textContent = 'Not Installed';
            statusBadge.className = 'status-badge not-installed';
            versionSpan.textContent = '';
            toggle.checked = false;
            addLogEntry(`Chocolatey package ${appId} is not installed`, 'INFO');
        }
    } catch (error) {
        statusBadge.textContent = 'Error';
        statusBadge.className = 'status-badge not-installed';
        addLogEntry(`Error refreshing Chocolatey package status for ${appId}: ${error.message}`, 'ERROR');
    } finally {
        button.disabled = false;
        refreshIcon.style.transform = 'rotate(0deg)';
    }
}

/**
 * Forces a bulk status check for all Chocolatey packages
 */
async function forceChocoBulkStatusCheck() {
    const bulkRefreshBtn = document.querySelector('#choco-status .bulk-refresh-btn');
    const packageCards = document.querySelectorAll('#choco-package-grid .package-card');

    addLogEntry('Starting forced Chocolatey bulk status check...', 'INFO');
    bulkRefreshBtn.disabled = true;

    try {
        // Clear the cached data
        sessionStorage.removeItem('chocoPackageData');
        sessionStorage.removeItem('chocoPackageStatus');
        
        // Reload the package list
        await loadChocoPackages();
        addLogEntry('Forced Chocolatey bulk status check completed successfully', 'SUCCESS');
    } catch (error) {
        addLogEntry(`Error during forced Chocolatey bulk status check: ${error.message}`, 'ERROR');

        packageCards.forEach(card => {
            const statusBadge = card.querySelector('.status-badge');
            statusBadge.textContent = 'Error';
            statusBadge.className = 'status-badge not-installed';
        });
    } finally {
        bulkRefreshBtn.disabled = false;
    }
}

/**
 * Retries a failed API call with exponential backoff
 */
async function retryWithBackoff(fn, retries = 3, backoff = 300) {
    try {
        return await fn();
    } catch (error) {
        if (retries === 0) throw error;

        await new Promise(resolve => setTimeout(resolve, backoff));
        return retryWithBackoff(fn, retries - 1, backoff * 2);
    }
}

/**
 * Makes an API call with timeout and retry support
 */
async function makeApiCall(url, options = {}, timeout = 5000) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
        const response = await retryWithBackoff(async () => {
            try {
                const res = await fetch(url, {
                    ...options,
                    signal: controller.signal
                });

                if (!res.ok) {
                    throw new Error(`HTTP error! status: ${res.status}`);
                }

                return res;
            } catch (error) {
                if (error.name === 'AbortError') {
                    throw new Error('Request timed out');
                }
                throw error;
            }
        });

        return await response.json();
    } finally {
        clearTimeout(timeoutId);
    }
}