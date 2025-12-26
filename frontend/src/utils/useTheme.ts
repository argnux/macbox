import { ref, watch, onMounted, onUnmounted } from 'vue'

type Theme = 'light' | 'dark' | 'system'

const theme = ref<Theme>('system')

export function useTheme() {
    const applyTheme = () => {
        const root = document.documentElement
        const isSystemDark = window.matchMedia('(prefers-color-scheme: dark)').matches

        if (theme.value === 'dark') {
            root.classList.add('dark')
        } else if (theme.value === 'light') {
            root.classList.remove('dark')
        } else {
            if (isSystemDark) {
                root.classList.add('dark')
            } else {
                root.classList.remove('dark')
            }
        }
    }

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    const handleSystemChange = () => {
        if (theme.value === 'system') {
            applyTheme()
        }
    }

    onMounted(() => {
        const savedTheme = localStorage.getItem('app-theme') as Theme
        if (savedTheme) {
            theme.value = savedTheme
        }

        applyTheme()

        mediaQuery.addEventListener('change', handleSystemChange)
    })

    onUnmounted(() => {
        mediaQuery.removeEventListener('change', handleSystemChange)
    })

    watch(theme, (newVal) => {
        localStorage.setItem('app-theme', newVal)
        applyTheme()
    })

    return {
        theme
    }
}
