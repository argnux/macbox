package services

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"

	goruntime "runtime"
	"strings"

	"github.com/blang/semver"
	"github.com/minio/selfupdate"
	"github.com/wailsapp/wails/v2/pkg/runtime"
)

const (
	GithubOwner = "argnux"
	GithubRepo  = "macbox"
)

type UpdateService struct {
	ctx            context.Context
	currentVersion string
}

type ReleaseAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

type ReleaseInfo struct {
	TagName string         `json:"tag_name"`
	Body    string         `json:"body"`
	Assets  []ReleaseAsset `json:"assets"`
}

func NewUpdateService(version string) *UpdateService {
	return &UpdateService{
		currentVersion: version,
	}
}

func (u *UpdateService) SetContext(ctx context.Context) {
	u.ctx = ctx
}

func (u *UpdateService) findCompatibleAssetUrl(assets []ReleaseAsset) string {
	targetArch := goruntime.GOARCH

	for _, asset := range assets {
		name := strings.ToLower(asset.Name)
		if strings.HasSuffix(name, ".zip") && strings.Contains(name, targetArch) {
			return asset.BrowserDownloadURL
		}
	}
	return ""
}

func (u *UpdateService) CheckForUpdates() *ReleaseInfo {
	if u.currentVersion == "dev" {
		runtime.LogInfo(u.ctx, "Update Check: Dev mode, skipping.")
		return nil
	}

	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", GithubOwner, GithubRepo)
	resp, err := http.Get(url)
	if err != nil {
		runtime.LogError(u.ctx, "Update Check Error: "+err.Error())
		return nil
	}
	defer resp.Body.Close()

	var release ReleaseInfo
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil
	}

	cleanTag := strings.TrimPrefix(release.TagName, "v")
	cleanCurrentTag := strings.TrimPrefix(u.currentVersion, "v")
	vNew, err1 := semver.Make(cleanTag)
	vCurrent, err2 := semver.Make(cleanCurrentTag)

	if err1 == nil && err2 == nil && vNew.GT(vCurrent) {
		if u.findCompatibleAssetUrl(release.Assets) == "" {
			runtime.LogInfo(u.ctx, "Update found ("+release.TagName+"), but assets are not ready yet.")
			return nil
		}

		return &release
	}

	return nil
}

func (u *UpdateService) PerformUpdate(release *ReleaseInfo) string {
	if u.currentVersion == "dev" {
		return "Cannot update in dev mode"
	}

	downloadUrl := u.findCompatibleAssetUrl(release.Assets)

	if downloadUrl == "" {
		return "No compatible update file found in release"
	}

	resp, err := http.Get(downloadUrl)
	if err != nil {
		return "Download failed: " + err.Error()
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	zipReader, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		return "Zip error: " + err.Error()
	}

	var binaryFile *zip.File

	for _, file := range zipReader.File {
		info := file.FileInfo()
		if info.IsDir() {
			continue
		}

		if goruntime.GOOS == "darwin" {
			if strings.HasSuffix(file.Name, "MacOS/macbox") {
				binaryFile = file
				break
			}
		} else if goruntime.GOOS == "windows" {
			if strings.HasSuffix(file.Name, ".exe") {
				binaryFile = file
				break
			}
		}
	}

	if binaryFile == nil {
		return "Executable not found inside zip update"
	}

	src, err := binaryFile.Open()
	if err != nil {
		return "Extract error: " + err.Error()
	}
	defer src.Close()

	err = selfupdate.Apply(src, selfupdate.Options{})
	if err != nil {
		return "Apply error: " + err.Error()
	}

	if goruntime.GOOS == "darwin" {
		exePath, _ := os.Executable()

		exec.Command("xattr", "-cr", exePath).Run()

		appBundlePath := strings.Split(exePath, "/Contents/MacOS")[0]
		exec.Command("xattr", "-cr", appBundlePath).Run()
	}

	return ""
}
