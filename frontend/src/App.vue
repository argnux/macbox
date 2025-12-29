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

        <el-card shadow="never" class="control-panel">
          <el-form :inline="true" size="default">

            <el-form-item label="Protocol">
              <el-select v-model="config.protocol" :disabled="isWatching" style="width: 100px">
                <el-option label="UDP" value="udp" />
                <el-option label="TCP" value="tcp" />
              </el-select>
            </el-form-item>

            <el-form-item label="Port">
              <el-input-number v-model="config.port" :disabled="isWatching" :min="1" :max="65535"
                controls-position="right" style="width: 120px" />
            </el-form-item>

            <el-form-item label="Parser">
              <el-select v-model="config.parser" placeholder="Select Parser" style="width: 220px"
                :loading="availableParsers.length === 0" :disabled="isWatching">
                <el-option v-for="item in availableParsers" :key="item.id" :label="item.name" :value="item.id">
                  <div class="parser-option">
                    <span class="option-name">{{ item.name }}</span>
                    <span class="option-desc" v-if="item.description">
                      {{ item.description }}
                    </span>
                  </div>
                </el-option>
              </el-select>
            </el-form-item>

            <el-form-item>
              <el-button :type="isWatching ? 'danger' : 'success'" @click="toggleWatcher" align="center"
                style="width: 140px">
                <el-icon v-if="!isWatching">
                  <VideoPlay />
                </el-icon>
                <el-icon v-else>
                  <VideoPause />
                </el-icon>
                <span>{{ isWatching ? 'Stop' : 'Start Listening' }}</span>
              </el-button>

              <el-button @click="clearLogs" :disabled="packets.length === 0">
                Clear
              </el-button>
            </el-form-item>

            <el-form-item style="float: right; margin-right: 0;">
              <el-switch v-model="autoScroll" active-text="Auto-scroll" />
            </el-form-item>
          </el-form>
        </el-card>

        <div class="workspace">

          <div class="packet-list" ref="listContainer">
            <el-table ref="tableRef" :data="packets" style="width: 100%; height: 100%" highlight-current-row
              @row-click="selectPacket" size="small" border>
              <el-table-column prop="timestamp" label="Time" width="105">
                <template #default="scope">
                  <span class="mono-text">{{ formatTime(scope.row.timestamp) }}</span>
                </template>
              </el-table-column>

              <el-table-column prop="size" label="Size" width="65" align="right">
                <template #default="scope">
                  {{ scope.row.size }} B
                </template>
              </el-table-column>

              <el-table-column prop="from_ip" label="From" width="150">
                <template #default="scope">
                  <span class="mono-text">{{ scope.row.from_ip }}</span>
                </template>
              </el-table-column>

              <el-table-column label="Preview" min-width="200">
                <template #default="scope">
                  <span class="mono-text preview-text">{{ getPreview(scope.row) }}</span>
                </template>
              </el-table-column>
            </el-table>
          </div>

          <div class="packet-details">
            <el-divider content-position="left">Packet Inspector</el-divider>

            <div v-if="selectedPacket" class="details-content">
              <div class="meta-row">
                <el-tag size="small">{{ selectedPacket.protocol.toUpperCase() }}</el-tag>
                <span class="meta-info">Port: {{ selectedPacket.port }}</span>
                <span class="meta-info">Size: {{ selectedPacket.size }} bytes</span>
              </div>

              <div class="section-title">Parsed Output ({{ selectedPacket.parser }})</div>
              <div class="code-block-wrapper">
                <template v-if="selectedPacket.parsed_data?.message" class="code-block raw-text">
                  {{ selectedPacket.parsed_data.message }}
                </template>

                <pre v-else class="code-block json-view" v-html="syntaxHighlight(selectedPacket.parsed_data)"></pre>
              </div>

              <div class="section-title">Raw Hex Dump</div>
              <div class="code-block hex-view">
                {{ toHexDump(selectedPacket.payload) }}
              </div>
            </div>

            <el-empty v-else description="Select a packet to inspect" image-size="60" />
          </div>
        </div>
      </div>

    </el-main>
  </el-container>
</template>

<script setup lang="ts">
import { ref, nextTick, onMounted, onBeforeUnmount, watch } from 'vue'
import { network, watcher, services } from '../wailsjs/go/models'
import { EventsOn } from '../wailsjs/runtime'
import {
  GetAppVersion, CreateInterface, UpdateInterface,
  DeleteInterface, CheckUpdate, InstallUpdate,
  StartPing, StopPing, GetAvailableParsers,
  GetWatcherState, SaveWatcherConfig, StartWatcher, StopWatcher
} from '../wailsjs/go/main/App'
import { isValidIP, maskToCidr, cidrToMask, isCidrInput } from './utils/netUtils'
import { useTheme } from './utils/useTheme'
import {
  Monitor, Tools, Setting,
  Moon, Sunny, Platform,
  Download, View,
  VideoPlay, VideoPause
} from '@element-plus/icons-vue'
import { ElMessage, ElMessageBox, ElTable } from 'element-plus'

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

interface UiPacket extends Omit<watcher.UDPPacket, 'convertValues' | 'payload' | 'timestamp'> {
  timestamp: Date
  payload: Uint8Array
  parsed_data: Record<string, any>
}

const availableParsers = ref<watcher.ParserMeta[]>([])
const tableRef = ref<InstanceType<typeof ElTable> | null>(null)
const autoScroll = ref<boolean>(true)
const packets = ref<UiPacket[]>([])
const selectedPacket = ref<UiPacket | null>(null)

const config = ref<watcher.WatcherConfig>(new watcher.WatcherConfig)
const isWatching = ref<boolean>(false)

const base64ToUint8Array = (base64: string): Uint8Array => {
  const binaryString = window.atob(base64)
  const len = binaryString.length
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i)
  }
  return bytes
}

const syntaxHighlight = (json: Record<string, any> | undefined): string => {
  if (!json) return ''
  let str = JSON.stringify(json, null, 2)
  str = str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  return str.replace(/("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g, (match) => {
    let cls = 'json-number'
    if (/^"/.test(match)) {
      if (/:$/.test(match)) {
        cls = 'json-key'
      } else {
        cls = 'json-string'
      }
    } else if (/true|false/.test(match)) {
      cls = 'json-boolean'
    } else if (/null/.test(match)) {
      cls = 'json-null'
    }
    return `<span class="${cls}">${match}</span>`
  })
}

const MAX_PACKETS = 1000
let cancelListener: (() => void) | null = null

const startListeningLogs = () => {
  cancelListener = EventsOn("packet_received", async (rawPacket: watcher.UDPPacket) => {
    let finalPayload: Uint8Array

    const rawPayload = rawPacket.payload as unknown

    if (typeof rawPayload === 'string') {
      finalPayload = base64ToUint8Array(rawPayload)
    } else if (Array.isArray(rawPayload)) {
      finalPayload = new Uint8Array(rawPayload)
    } else {
      finalPayload = new Uint8Array(0)
    }

    const packet: UiPacket = {
      ...rawPacket,
      timestamp: new Date(rawPacket.timestamp as unknown as string),
      payload: finalPayload
    }

    packets.value.push(packet)

    if (packets.value.length > MAX_PACKETS) {
      packets.value.shift()
    }

    if (autoScroll.value) {
      await nextTick()
      scrollToBottom()
    }
  })
}

const stopListeningLogs = () => {
  if (cancelListener) {
    cancelListener()
    cancelListener = null
  }
}

const initData = async () => {
  try {
    const [parsers, state] = await Promise.all([
      GetAvailableParsers(),
      GetWatcherState()
    ])

    availableParsers.value = parsers

    config.value = state.config
    isWatching.value = state.running

    const parserExists = parsers.find(p => p.id === config.value.parser)
    if (!parserExists && parsers.length > 0) {
      config.value.parser = parsers[0].id
    }
  } catch (e) {
    console.error(e)
  }
}

watch(config, (newConfig) => {
  SaveWatcherConfig(newConfig)
}, { deep: true })

const toggleWatcher = () => {
  if (isWatching.value) {
    stopListeningLogs()
    isWatching.value = false
    StopWatcher()
  } else {
    startListeningLogs()
    isWatching.value = true
    StartWatcher()
  }
}

const clearLogs = () => {
  packets.value = []
  selectedPacket.value = null
}

const selectPacket = (row: UiPacket) => {
  selectedPacket.value = row
}

const formatTime = (date: Date): string => {
  return date.toLocaleTimeString('en-US', { hour12: false }) + '.' + date.getMilliseconds().toString().padStart(3, '0')
}

const getPreview = (packet: watcher.UDPPacket): string => {
  const slice = packet.payload.slice(0, 12)
  const hexString = Array.from(slice)
    .map(b => b.toString(16).padStart(2, '0').toUpperCase())
    .join(' ')

  return hexString + (packet.size > 12 ? '...' : '')
}

const toHexDump = (buffer: Uint8Array): string => {
  const hex = Array.from(buffer).map(b => b.toString(16).padStart(2, '0').toUpperCase())
  let output = ''
  for (let i = 0; i < hex.length; i += 16) {
    const chunk = hex.slice(i, i + 16)
    output += chunk.join(' ') + '\n'
  }
  return output
}

onBeforeUnmount(() => {
  stopListeningLogs()
})

const scrollToBottom = async () => {
  await nextTick()

  if (tableRef.value) {
    const scrollWrapper = tableRef.value.$el.querySelector('.el-scrollbar__wrap')
    if (scrollWrapper) {
      scrollWrapper.scrollTop = scrollWrapper.scrollHeight
      return
    }
  }

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

  initData()

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

.watcher-view {
  height: 100%;
  display: flex;
  flex-direction: column;
  gap: 10px;
  overflow: hidden;
}

.control-panel {
  flex-shrink: 0;
}

.control-panel :deep(.el-card__body) {
  padding: 10px 15px;
}

.control-panel :deep(.el-form--inline) {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  overflow-x: auto;
}

.control-panel :deep(.el-form-item) {
  margin-bottom: 0;
  margin-right: 12px;
  flex-shrink: 0;
}

.control-panel :deep(.el-form-item:last-child) {
  margin-right: 0;
  margin-left: auto;
}

.workspace {
  flex-grow: 1;
  height: 0;

  display: flex;
  gap: 0;
  border: 1px solid var(--el-border-color-light);
  border-radius: 4px;
  background-color: var(--el-bg-color);
}

.packet-list {
  flex: 2;
  position: relative;
  height: 100%;
  overflow: hidden;
  border-right: 1px solid var(--el-border-color-light);
}

.packet-details {
  flex: 1;
  height: 100%;
  display: flex;
  flex-direction: column;
  background-color: var(--el-bg-color-overlay);
  overflow: hidden;
  min-width: 0;
}

.details-content {
  padding: 15px;
  overflow-y: auto;
  height: 100%;
}

.meta-row {
  margin-bottom: 15px;
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px 15px;
  font-size: 13px;
  color: var(--el-text-color-regular);
}

.section-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--el-text-color-secondary);
  margin-top: 20px;
  margin-bottom: 8px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.mono-text {
  font-family: 'Consolas', 'Monaco', monospace;
  font-size: 12px;
}

.preview-text {
  color: var(--el-color-primary);
  opacity: 0.9;
}

.code-block {
  text-align: left;
  background-color: var(--el-fill-color-lighter);
  border: 1px solid var(--el-border-color-lighter);
  color: var(--el-text-color-primary);
  padding: 12px;
  border-radius: 4px;

  font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
  font-size: 12px;
  line-height: 1.5;
  max-height: 300px;
  overflow: auto;
}

.json-view {
  margin: 0;
  white-space: pre;
}

.raw-text {
  white-space: pre-wrap;
}

:deep(.json-key) {
  color: var(--el-color-primary);
  font-weight: bold;
}

:deep(.json-string) {
  color: var(--el-color-success);
}

:deep(.json-number) {
  color: var(--el-color-warning);
}

:deep(.json-boolean) {
  color: var(--el-color-danger);
  font-weight: bold;
}

:deep(.json-null) {
  color: var(--el-text-color-secondary);
  font-style: italic;
}

.hex-view {
  opacity: 0.9;
}

.parsed-view {
  color: var(--el-color-primary-dark-2);
  font-weight: 500;
}

.parser-option {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  gap: 20px;
}

.option-name {
  font-weight: 500;
  white-space: nowrap;
}

.option-desc {
  color: var(--el-text-color-secondary);
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;

  max-width: 150px;
  text-align: right;
}
</style>
