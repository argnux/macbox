<template>
  <el-container class="layout-container">
    <el-aside width="200px" class="sidebar">
      <div class="logo-area">
        <h3>MacBox</h3>
      </div>

      <el-menu :default-active="activeTab" class="el-menu-vertical" @select="(index: string) => activeTab = index">
        <el-menu-item index="network">
          <el-icon>
            <Monitor />
          </el-icon>
          <span>Interfaces</span>
        </el-menu-item>

        <el-menu-item index="tools">
          <el-icon>
            <Tools />
          </el-icon>
          <span>Tools</span>
        </el-menu-item>

        <el-menu-item index="watcher">
          <el-icon>
            <View />
          </el-icon>
          <span>Watcher</span>
        </el-menu-item>

        <el-menu-item index="settings" disabled>
          <el-icon>
            <Setting />
          </el-icon>
          <span>Settings</span>
        </el-menu-item>
      </el-menu>

      <div class="sidebar-footer">
        <el-dropdown trigger="click" @command="(cmd: any) => theme = cmd">
          <span class="theme-trigger">
            <el-icon :size="16">
              <component :is="getCurrentThemeIcon()" />
            </el-icon>
            <span class="theme-label">{{ theme.charAt(0).toUpperCase() + theme.slice(1) }}</span>
          </span>

          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="light">
                <el-icon>
                  <Sunny />
                </el-icon> Light
              </el-dropdown-item>
              <el-dropdown-item command="dark">
                <el-icon>
                  <Moon />
                </el-icon> Dark
              </el-dropdown-item>
              <el-dropdown-item command="system">
                <el-icon>
                  <Platform />
                </el-icon> System
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>

        <div v-if="updateAvailable" class="update-area">
          <el-button type="primary" size="small" :loading="isUpdating" @click="handleUpdate" round>
            <el-icon class="el-icon--left">
              <Download />
            </el-icon>
            Update to {{ updateAvailable.tag_name }}
          </el-button>
        </div>

        <div class="version-text">{{ appVersion }}</div>
      </div>
    </el-aside>
    <el-main class="main-content">

      <div v-if="activeTab === 'network'" class="view-container">
        <el-table :data="hardwareList" style="width: 100%" border row-key="device">

          <el-table-column type="expand">
            <template #default="props">
              <div class="nested-container">

                <div class="nested-header">
                  <div class="title-area">
                    <h4>Services on {{ props.row.name }} ({{ props.row.device }})</h4>
                  </div>

                  <el-button v-if="!isAdding(props.row.device)" type="primary" size="small"
                    @click="startAdding(props.row.device)">
                    + New Service
                  </el-button>

                  <div v-else class="add-form-inline">
                    <el-input v-model="newServiceState[props.row.device].name" placeholder="Service Name (Unique)"
                      size="small" style="width: 180px" />

                    <el-button type="success" size="small" @click="saveNewService(props.row.device, props.row.name)">
                      Create
                    </el-button>
                    <el-button size="small" @click="cancelAdding(props.row.device)">
                      Cancel
                    </el-button>
                  </div>
                </div>

                <el-table :data="props.row.logicInterfaces" border size="small" row-key="id">

                  <el-table-column label="Name" width="200">
                    <template #default="scope">
                      <el-input v-if="isEditing(scope.row.id)" v-model="editState[scope.row.id].name" size="small" />
                      <span v-else>{{ scope.row.name }}</span>
                    </template>
                  </el-table-column>

                  <el-table-column label="Method" width="150">
                    <template #default="scope">

                      <div v-if="isEditing(scope.row.id)" class="edit-cell-wrapper">
                        <el-select v-model="editState[scope.row.id].method" size="small" class="full-width-select">
                          <el-option label="DHCP" value="DHCP" />
                          <el-option label="Manual" value="Manual" />
                        </el-select>
                      </div>

                      <div v-else class="view-cell-wrapper">
                        <el-tag :type="scope.row.method === 'DHCP' ? '' : 'warning'">
                          {{ scope.row.method }}
                        </el-tag>
                      </div>

                    </template>
                  </el-table-column>

                  <el-table-column label="IP Address" width="160">
                    <template #default="scope">
                      <div v-if="isEditing(scope.row.id)" class="edit-cell-wrapper">
                        <el-input v-model="editState[scope.row.id].ip"
                          :disabled="editState[scope.row.id].method === 'DHCP'" size="small"
                          :class="{ 'input-error': editState[scope.row.id].method === 'Manual' && !isValidIP(editState[scope.row.id].ip) }" />
                      </div>
                      <span v-else>{{ scope.row.ip }}</span>
                    </template>
                  </el-table-column>

                  <el-table-column label="Mask / CIDR" width="160">
                    <template #default="scope">
                      <div v-if="isEditing(scope.row.id)" class="edit-cell-wrapper">
                        <el-input v-model="editState[scope.row.id].mask"
                          :disabled="editState[scope.row.id].method === 'DHCP'" placeholder="e.g. 255.255.255.0 or /24"
                          size="small" />
                      </div>
                      <span v-else>{{ displayMask(scope.row.mask) }}</span>
                    </template>
                  </el-table-column>

                  <el-table-column label="Gateway">
                    <template #default="scope">
                      <el-input v-if="isEditing(scope.row.id)" v-model="editState[scope.row.id].gateway"
                        :disabled="editState[scope.row.id].method === 'DHCP'" size="small" />
                      <span v-else>{{ scope.row.gateway }}</span>
                    </template>
                  </el-table-column>

                  <el-table-column label="Actions" width="140" fixed="right">
                    <template #default="scope">

                      <div v-if="isEditing(scope.row.id)">
                        <el-button type="success" link size="small" @click="saveEdit(scope.row.id)">Save</el-button>
                        <el-button type="info" link size="small" @click="cancelEdit(scope.row.id)">Cancel</el-button>
                      </div>

                      <div v-else>
                        <el-button type="primary" link size="small" @click="startEdit(scope.row)">Edit</el-button>
                        <el-button type="danger" link size="small"
                          @click="deleteService(scope.row.name)">Del</el-button>
                      </div>

                    </template>
                  </el-table-column>

                </el-table>
              </div>
            </template>
          </el-table-column>

          <el-table-column label="State" width="80" align="center">
            <template #default="scope">
              <el-tooltip :content="scope.row.isActive ? 'Active (Link Up)' : 'Inactive (Link Down)'" placement="top"
                :hide-after="0">
                <div :class="['status-dot', scope.row.isActive ? 'active' : 'inactive']"></div>
              </el-tooltip>
            </template>
          </el-table-column>

          <el-table-column prop="name" label="Hardware Port" />
          <el-table-column prop="device" label="Device" width="100" />
          <el-table-column prop="mac" label="MAC" width="160" />

        </el-table>
      </div>

      <div v-else-if="activeTab === 'tools'" class="view-container tools-view">
        <div class="tools-collapse">
          <el-collapse v-model="activeTool" accordion>
            <el-collapse-item title="Ping Tool" name="1">

              <div class="controls-row">
                <el-input v-model="targetIp" placeholder="IP Address" style="width: 180px" :disabled="isPinging" />

                <el-checkbox v-model="isInfinite" label="Infinite" border :disabled="isPinging"
                  style="margin-right: 10px;" />

                <el-input-number v-if="!isInfinite" v-model="packetCount" :min="1" :max="100" style="width: 100px"
                  :disabled="isPinging" controls-position="right" />

                <el-button type="primary" @click="handleStartPing" :disabled="isPinging || !targetIp"
                  :loading="isPinging">
                  {{ isPinging ? 'Pinging...' : 'Start' }}
                </el-button>

                <el-button type="danger" @click="handleStopPing" :disabled="!isPinging">
                  Stop
                </el-button>
              </div>

              <div class="log-container">
                <el-input ref="textareaRef" v-model="pingLogs" type="textarea" :rows="8" readonly
                  class="console-output" />
              </div>

            </el-collapse-item>
          </el-collapse>
        </div>
      </div>

      <div v-else-if="activeTab === 'watcher'" class="view-container watcher-view">
        <el-empty description="Watcher Coming Soon">
          <template #extra>
            <p>Watch UDP (and may be TCP) packets on port. Parse it or not. Whatever you want.</p>
          </template>
        </el-empty>
      </div>

    </el-main>
  </el-container>
</template>

<script setup lang="ts">
import { ref, nextTick, onMounted } from 'vue'
import { network, services } from '../wailsjs/go/models'
import { EventsOn } from '../wailsjs/runtime'
import {
  GetAppVersion, CreateInterface, UpdateInterface,
  DeleteInterface, CheckUpdate, InstallUpdate,
  StartPing, StopPing
} from '../wailsjs/go/main/App'
import { isValidIP, maskToCidr, cidrToMask, isCidrInput } from './utils/netUtils'
import { useTheme } from './utils/useTheme'
import {
  Monitor, Tools, Setting,
  Moon, Sunny, Platform,
  Download, View
} from '@element-plus/icons-vue'
import { ElMessage, ElMessageBox } from 'element-plus'

const { theme } = useTheme()

const appVersion = ref("")
const activeTab = ref('network')
const hardwareList = ref<network.HardwareInterface[]>([])

const activeTool = ref('0')
const targetIp = ref('')
const packetCount = ref(4)
const pingLogs = ref('')
const isInfinite = ref(false)
const isPinging = ref(false)
const textareaRef = ref<any>(null)

const scrollToBottom = async () => {
  await nextTick()
  if (textareaRef.value) {
    const innerTextarea = textareaRef.value.textarea
    if (innerTextarea) {
      innerTextarea.scrollTop = innerTextarea.scrollHeight
    }
  }
}

const handleStartPing = async () => {
  if (!targetIp.value) return

  pingLogs.value = `> Pinging ${targetIp.value}...\n`
  isPinging.value = true

  try {
    const count = isInfinite.value ? 0 : packetCount.value
    await StartPing(targetIp.value, count)
  } catch (err) {
    pingLogs.value += `\nError: ${err}`
  } finally {
    isPinging.value = false
    pingLogs.value += '\n> Done.'
    scrollToBottom()
  }
}

const handleStopPing = async () => {
  await StopPing()
  isPinging.value = false
  pingLogs.value += '\n> Stopped by user.'
}

const updateAvailable = ref<services.ReleaseInfo>()
const isUpdating = ref(false)

const handleNetworkUpdate = (data: network.HardwareInterface[]) => {
  hardwareList.value = data
}

onMounted(async () => {
  EventsOn("network-update", handleNetworkUpdate)

  EventsOn("ping-log", (msg: string) => {
    pingLogs.value += msg
    scrollToBottom()
  })

  appVersion.value = await GetAppVersion()

  const release = await CheckUpdate()
  if (release) {
    updateAvailable.value = release
  }
})

const handleUpdate = async () => {
  if (!updateAvailable.value) return

  isUpdating.value = true
  const err = await InstallUpdate(updateAvailable.value)

  if (err) {
    ElMessage.error("Update failed: " + err)
    isUpdating.value = false
  } else {
    ElMessage.success("Update installed! Restarting...")
    setTimeout(() => {
      ElMessage.success("Update complete. Please restart the app.")
    }, 1000)
  }
}

const getCurrentThemeIcon = () => {
  if (theme.value === 'dark') return Moon
  if (theme.value === 'light') return Sunny
  return Platform
}

const editState = ref<Record<string, network.LogicInterface>>({})

const isEditing = (id: string) => !!editState.value[id]

const startEdit = (row: network.LogicInterface) => {
  editState.value[row.id] = JSON.parse(JSON.stringify(row))
}

const cancelEdit = (id: string) => {
  delete editState.value[id]
}

const saveEdit = async (id: string) => {
  const draft = editState.value[id]

  if (draft.method === 'Manual') {
    if (!isValidIP(draft.ip)) {
      ElMessage.error("Invalid IP Address format")
      return
    }
    if (draft.gateway && !isValidIP(draft.gateway)) {
      ElMessage.error("Invalid Gateway format")
      return
    }
  }

  let finalMask = draft.mask
  if (isCidrInput(draft.mask)) {
    const converted = cidrToMask(draft.mask)
    if (!converted) {
      ElMessage.error("Invalid CIDR mask")
      return
    }
    finalMask = converted
  } else if (!isValidIP(draft.mask) && draft.method === 'Manual') {
    ElMessage.error("Invalid Subnet Mask format")
    return
  }

  const payload = {
    oldName: draft.id,
    newName: draft.name,
    method: draft.method,
    ip: draft.ip,
    mask: finalMask,
    gateway: draft.gateway
  }

  const err = await UpdateInterface(payload)
  if (err) {
    ElMessage.error("Failed to update: " + err)
  } else {
    ElMessage.success("Updated successfully")
    delete editState.value[id]
  }
}

const deleteService = async (name: string) => {
  try {
    await ElMessageBox.confirm(
      `Are you sure you want to permanently delete the service "${name}"?`,
      'Warning',
      {
        confirmButtonText: 'Delete',
        cancelButtonText: 'Cancel',
        type: 'warning',
      }
    )

    const err = await DeleteInterface(name)
    if (err) {
      ElMessage.error(err)
    } else {
      ElMessage.success("Deleted successfully")
    }
  } catch (error) {
    console.log("Delete canceled")
  }
}

const newServiceState = ref<Record<string, { name: string }>>({})

const isAdding = (deviceID: string) => !!newServiceState.value[deviceID]

const startAdding = (deviceID: string) => {
  newServiceState.value[deviceID] = { name: "" }
}

const cancelAdding = (deviceID: string) => {
  delete newServiceState.value[deviceID]
}

const saveNewService = async (deviceID: string, hardwarePortName: string) => {
  const form = newServiceState.value[deviceID]
  if (!form.name) {
    ElMessage.warning("Service name is required")
    return
  }

  const err = await CreateInterface(hardwarePortName, form.name)
  if (err) {
    ElMessage.error(err)
  } else {
    ElMessage.success(`Service ${form.name} created!`)
    delete newServiceState.value[deviceID]
  }
}

const displayMask = (mask: string) => {
  const cidr = maskToCidr(mask)
  return cidr ? `${mask} (${cidr})` : mask
}
</script>

<style scoped>
.layout-container {
  height: 100vh;
  display: flex;
}

.sidebar {
  background-color: var(--el-bg-color-overlay);
  border-right: 1px solid var(--el-border-color);
  display: flex;
  flex-direction: column;
  transition: background-color 0.3s;
}

.logo-area {
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-bottom: 1px solid var(--el-border-color);
  background: var(--el-bg-color);
}

.logo-area h3 {
  margin: 0;
  color: #409EFF;
}

.el-menu-vertical {
  border-right: none;
  background-color: transparent;
  flex: 1;
}

.sidebar-footer {
  padding: 15px;
  border-top: 1px solid var(--el-border-color);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}

.theme-trigger {
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 10px;
  border-radius: 4px;
  transition: background 0.2s;
  color: var(--el-text-color-regular);
}

.theme-trigger:hover {
  background-color: var(--el-fill-color);
}

.theme-label {
  font-size: 12px;
}

.version-text {
  font-size: 10px;
  color: var(--el-text-color-secondary);
}

.main-content {
  padding: 20px;
  background-color: var(--el-bg-color);
  color: var(--el-text-color-primary);
}

.view-container {
  height: 100%;
}

.tools-collapse {
  width: 100%;
  height: 100%;
}

.controls-row {
  display: flex;
  gap: 10px;
  margin-bottom: 15px;
  align-items: center;
}

.log-container {
  margin-top: 10px;
}

.console-output :deep(.el-textarea__inner) {
  font-family: 'Menlo', 'Monaco', 'Consolas', monospace;
  font-size: 12px;
  line-height: 1.4;

  background-color: var(--el-fill-color-light);
  color: var(--el-text-color-regular);
  border-color: var(--el-border-color);

  transition: all 0.3s;
}

html.dark .console-output :deep(.el-textarea__inner) {
  background-color: #1e1e1e;
  color: #67C23A;
  border-color: #4c4d4f;
}

.tools-view {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 80vh;
}

.status-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  margin: 0 auto;
  position: relative;
  display: block;
}

.active {
  background-color: #67C23A;
  /* Element Plus Success Green */
  box-shadow: 0 0 5px rgba(103, 194, 58, 0.5);
}

.inactive {
  background-color: #909399;
  /* Element Plus Info Gray */
  opacity: 0.6;
}

.input-error :deep(.el-input__wrapper) {
  box-shadow: 0 0 0 1px #F56C6C inset !important;
}

.input-error :deep(input) {
  color: #F56C6C;
}

.nested-container {
  padding: 10px 20px;
  background: var(--el-bg-color);
}

.nested-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
  height: 40px;
}

.add-form-inline {
  display: flex;
  gap: 10px;
  align-items: center;
}

.edit-cell-wrapper {
  width: 100%;
  display: block;
}

.full-width-select {
  width: 100% !important;
}

:deep(.full-width-select .el-input),
:deep(.full-width-select .el-input__wrapper) {
  width: 100% !important;
  box-sizing: border-box;
}

.view-cell-wrapper {
  display: flex;
  align-items: center;
  height: 24px;
}

.update-area {
  margin-bottom: 10px;
  animation: fadeIn 0.5s;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(5px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
