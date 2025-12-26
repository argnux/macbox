export const isValidIP = (ip: string): boolean => {
    const regex = /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/
    return regex.test(ip)
}

export const maskToCidr = (mask: string): string => {
    if (!isValidIP(mask)) return ""
    const parts = mask.split('.').map(Number)
    let bits = 0
    for (const part of parts) {
        bits += (part >>> 0).toString(2).split('1').length - 1
    }
    return "/" + bits
}

export const cidrToMask = (cidr: string): string => {
    let bits = parseInt(cidr.replace("/", ""))
    if (isNaN(bits) || bits < 0 || bits > 32) return ""
    
    const mask = []
    for (let i = 0; i < 4; i++) {
        const n = Math.min(bits, 8)
        mask.push(256 - Math.pow(2, 8 - n))
        bits -= n
    }
    return mask.join('.')
}

export const isCidrInput = (val: string): boolean => {
    return val.startsWith("/") || (val.length <= 2 && !val.includes("."))
}
