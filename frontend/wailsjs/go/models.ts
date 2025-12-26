export namespace network {
	
	export class LogicInterface {
	    id: string;
	    name: string;
	    device: string;
	    ip: string;
	    mask: string;
	    gateway: string;
	    method: string;
	
	    static createFrom(source: any = {}) {
	        return new LogicInterface(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.device = source["device"];
	        this.ip = source["ip"];
	        this.mask = source["mask"];
	        this.gateway = source["gateway"];
	        this.method = source["method"];
	    }
	}
	export class HardwareInterface {
	    name: string;
	    device: string;
	    mac: string;
	    isActive: boolean;
	    logicInterfaces: LogicInterface[];
	
	    static createFrom(source: any = {}) {
	        return new HardwareInterface(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.device = source["device"];
	        this.mac = source["mac"];
	        this.isActive = source["isActive"];
	        this.logicInterfaces = this.convertValues(source["logicInterfaces"], LogicInterface);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	export class UpdatePayload {
	    oldName: string;
	    newName: string;
	    method: string;
	    ip: string;
	    mask: string;
	    gateway: string;
	
	    static createFrom(source: any = {}) {
	        return new UpdatePayload(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.oldName = source["oldName"];
	        this.newName = source["newName"];
	        this.method = source["method"];
	        this.ip = source["ip"];
	        this.mask = source["mask"];
	        this.gateway = source["gateway"];
	    }
	}

}

export namespace services {
	
	export class ReleaseAsset {
	    name: string;
	    browser_download_url: string;
	
	    static createFrom(source: any = {}) {
	        return new ReleaseAsset(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.browser_download_url = source["browser_download_url"];
	    }
	}
	export class ReleaseInfo {
	    tag_name: string;
	    body: string;
	    assets: ReleaseAsset[];
	
	    static createFrom(source: any = {}) {
	        return new ReleaseInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.tag_name = source["tag_name"];
	        this.body = source["body"];
	        this.assets = this.convertValues(source["assets"], ReleaseAsset);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}

}

