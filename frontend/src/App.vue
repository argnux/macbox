<template>
  <div class="container">
    <el-table :data="hardwareList" style="width: 100%" border row-key="device">
      
      <el-table-column type="expand">
        <template #default="props">
          <div class="nested-container">
            
            <div class="nested-header">
              <div class="title-area">
                <h4>Services on {{ props.row.name }} ({{ props.row.device }})</h4>
              </div>
              
              <el-button 
                v-if="!isAdding(props.row.device)"
                type="primary" size="small" 
                @click="startAdding(props.row.device)">
                + New Service
              </el-button>

              <div v-else class="add-form-inline">
                <el-input 
                  v-model="newServiceState[props.row.device].name" 
                  placeholder="Service Name (Unique)" 
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
                  <el-input v-if="isEditing(scope.row.id)" 
                            v-model="editState[scope.row.id].name" size="small" />
                  <span v-else>{{ scope.row.name }}</span>
                </template>
              </el-table-column>

              <el-table-column label="Method" width="150">
                <template #default="scope">
                  
                  <div v-if="isEditing(scope.row.id)" class="edit-cell-wrapper">
                    <el-select 
                      v-model="editState[scope.row.id].method" 
                      size="small"
                      class="full-width-select" 
                    >
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
                    <el-input 
                        v-model="editState[scope.row.id].ip" 
                        :disabled="editState[scope.row.id].method === 'DHCP'"
                        size="small"
                        :class="{ 'input-error': editState[scope.row.id].method === 'Manual' && !isValidIP(editState[scope.row.id].ip) }"
                    />
                  </div>
                  <span v-else>{{ scope.row.ip }}</span>
                </template>
              </el-table-column>

              <el-table-column label="Mask / CIDR" width="160">
                <template #default="scope">
                  <div v-if="isEditing(scope.row.id)" class="edit-cell-wrapper">
                    <el-input 
                        v-model="editState[scope.row.id].mask"
                        :disabled="editState[scope.row.id].method === 'DHCP'" 
                        placeholder="e.g. 255.255.255.0 or /24"
                        size="small"
                    />
                  </div>
                  <span v-else>{{ displayMask(scope.row.mask) }}</span>
                </template>
              </el-table-column>

              <el-table-column label="Gateway">
                <template #default="scope">
                   <el-input v-if="isEditing(scope.row.id)" 
                             v-model="editState[scope.row.id].gateway"
                             :disabled="editState[scope.row.id].method === 'DHCP'"
                             size="small" />
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
                    <el-button type="danger" link size="small" @click="deleteService(scope.row.name)">Del</el-button>
                  </div>

                </template>
              </el-table-column>

            </el-table>
          </div>
        </template>
      </el-table-column>

      <el-table-column label="State" width="80" align="center">
        <template #default="scope">
          <el-tooltip 
            :content="scope.row.isActive ? 'Active (Link Up)' : 'Inactive (Link Down)'" 
            placement="top"
            :hide-after="0"
          >
            <div :class="['status-dot', scope.row.isActive ? 'active' : 'inactive']"></div>
          </el-tooltip>
        </template>
      </el-table-column>

      <el-table-column prop="name" label="Hardware Port" />
      <el-table-column prop="device" label="Device" width="100" />
      <el-table-column prop="mac" label="MAC" width="160" />

    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { network } from '../wailsjs/go/models'
import { EventsOn } from '../wailsjs/runtime'
import { CreateInterface, UpdateInterface, DeleteInterface } from '../wailsjs/go/main/App'
import { isValidIP, maskToCidr, cidrToMask, isCidrInput } from './utils/netUtils'
import { ElMessage, ElMessageBox } from 'element-plus'

// Стейт данных
const hardwareList = ref<network.HardwareInterface[]>([])

const handleNetworkUpdate = (data: network.HardwareInterface[]) => {
  hardwareList.value = data
}

onMounted(() => {
  const cancelSubscription = EventsOn("network-update", handleNetworkUpdate)
})

// --- Actions ---

const editState = ref<Record<string, network.LogicInterface>>({})

const isEditing = (id: string) => !!editState.value[id]

const startEdit = (row: network.LogicInterface) => {
  // Делаем глубокую копию строки, чтобы не менять таблицу до сохранения
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
      // Валидация Gateway (если он не пустой)
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
  
  // Формируем пейлоад для Go
  // draft.id - это СТАРОЕ имя (так как мы использовали имя как ID при загрузке)
  // draft.name - это НОВОЕ имя (если юзер его поменял в инпуте)
  const payload = {
    oldName: draft.id,
    newName: draft.name,
    method:  draft.method,
    ip:      draft.ip,
    mask:    finalMask, // Отправляем всегда Decimal
    gateway: draft.gateway
  }

  const err = await UpdateInterface(payload)
  if (err) {
    ElMessage.error("Failed to update: " + err)
  } else {
    ElMessage.success("Updated successfully")
    delete editState.value[id]
    // Тут можно дернуть ручное обновление списка, если events приходят редко
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
    
    // Если юзер нажал ОК, код пойдет дальше. Если Cancel - вылетит в catch
    const err = await DeleteInterface(name)
    if (err) {
      ElMessage.error(err)
    } else {
      ElMessage.success("Deleted successfully")
      // Тут можно вызвать обновление данных, если events задерживаются
    }
  } catch (error) {
    // Юзер нажал отмену, ничего не делаем
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

  // Вызываем Go
  const err = await CreateInterface(hardwarePortName, form.name)
  if (err) {
    ElMessage.error(err)
  } else {
    ElMessage.success(`Service ${form.name} created!`)
    delete newServiceState.value[deviceID]
    // Новый сервис появится в таблице сам, когда прилетит event "network-update"
  }
}

const displayMask = (mask: string) => {
    // Пытаемся показать красиво (CIDR). Если маска "кривая", показываем как есть.
    const cidr = maskToCidr(mask)
    return cidr ? `${mask} (${cidr})` : mask
}
</script>

<style scoped>
.status-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  margin: 0 auto;
  position: relative;
  display: block;
}

.active { 
  background-color: #67C23A; /* Element Plus Success Green */
  box-shadow: 0 0 5px rgba(103, 194, 58, 0.5);
}

.inactive { 
  background-color: #909399; /* Element Plus Info Gray */
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
  background: #fafafa;
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
</style>
