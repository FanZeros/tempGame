-- ============================================================================
-- FileUpload Widget
-- File upload interface with drag-and-drop support
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class FileUploadProps : WidgetProps
---@field variant? string "dropzone" | "button" | "inline" (default: "dropzone")
---@field multiple? boolean Allow multiple file selection (default: false)
---@field accept? string Accepted file types e.g. "image/*", ".pdf,.doc" (default: "*")
---@field maxSize? number Max file size in bytes
---@field maxFiles? number Max number of files (default: 10)
---@field showFileList? boolean Show uploaded file list (default: true)
---@field showProgress? boolean Show upload progress (default: false)
---@field icon? string Upload icon (default: "📁")
---@field label? string Upload label text
---@field hint? string Hint text below label
---@field disabled? boolean Disabled state (default: false)
---@field showHeader? boolean Show header section above dropzone (default: false)
---@field headerText? string Header text (default: "Upload area")
---@field dropzoneHeight? number Drop zone height (default: 100)
---@field dropzoneBgColor? RGBAColor|string Drop zone background color (default: surfaceAlt)
---@field dropzoneBorderColor? RGBAColor|string Drop zone border color
---@field dropzoneBorderWidth? number Drop zone border width (default: 2)
---@field dropzoneHoverBorderColor? RGBAColor|string Drop zone hover border color
---@field dropzoneDraggingBorderColor? RGBAColor|string Drop zone dragging border color
---@field dropzoneBorderStyle? string "solid" | "dashed" (default: "dashed")
---@field iconSize? number Icon wrapper size (default: 46)
---@field iconBgColor? RGBAColor|string Icon wrapper background color
---@field iconColor? RGBAColor|string Icon color (default: textSecondary)
---@field iconRadius? number Icon wrapper corner radius (default: 12)
---@field labelFontWeight? string Label font weight (default: fontWeight)
---@field labelTextColor? RGBAColor|string Label text color
---@field hintTextColor? RGBAColor|string Hint text color
---@field onFileSelect? fun(upload: FileUpload, file: table) File selection callback
---@field onFileRemove? fun(upload: FileUpload, file: table) File removal callback
---@field onUploadProgress? fun(upload: FileUpload, file: table, progress: number) Progress callback
---@field onUploadComplete? fun(upload: FileUpload, file: table) Upload complete callback
---@field onError? fun(upload: FileUpload, message: string) Error callback

---@class FileUpload : Widget
---@overload fun(props?: FileUploadProps): FileUpload
---@field props FileUploadProps
---@field new fun(self, props?: FileUploadProps): FileUpload
local FileUpload = Widget:Extend("FileUpload")

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props FileUploadProps?
function FileUpload:Init(props)
    props = props or {}

    -- Apply theme defaults
    local themeStyle = Theme.ComponentStyle("FileUpload")
    Style.ApplyDefaults(props, themeStyle)

    -- FileUpload props
    self.variant_ = props.variant or "dropzone"  -- dropzone, button, inline
    self.multiple_ = props.multiple or false
    self.accept_ = props.accept or "*"  -- File types: "image/*", ".pdf,.doc", etc.
    self.maxSize_ = props.maxSize  -- Max file size in bytes
    self.maxFiles_ = props.maxFiles or 10

    -- Visual
    self.showFileList_ = props.showFileList ~= false  -- default true
    self.showProgress_ = props.showProgress or false
    self.icon_ = props.icon or "📁"
    self.label_ = props.label or "Drop files here or click to upload"
    self.hint_ = props.hint

    -- State
    self.files_ = {}  -- { name, size, type, progress, status }
    self.isDragging_ = false
    self.isHovered_ = false

    -- Callbacks
    self.onFileSelect_ = props.onFileSelect
    self.onFileRemove_ = props.onFileRemove
    self.onUploadProgress_ = props.onUploadProgress
    self.onUploadComplete_ = props.onUploadComplete
    self.onError_ = props.onError

    -- Disabled state
    self.disabled_ = props.disabled or false

    -- Header
    self.showHeader_ = props.showHeader or false
    self.headerText_ = props.headerText or "Upload area"
    self.headerHeight_ = self.showHeader_ and 44 or 0

    -- Sizes
    self.fileItemHeight_ = 48
    self.dropzoneHeight_ = props.dropzoneHeight or 100
    self.baseHeight_ = nil  -- Will be set after Init

    Widget.Init(self, props)

    -- Store base height (without file list)
    self.baseHeight_ = self:GetBaseHeight()
    self:UpdateTotalHeight()
end

-- ============================================================================
-- Height Management
-- ============================================================================

function FileUpload:GetBaseHeight()
    if self.variant_ == "dropzone" then
        return self.headerHeight_ + self.dropzoneHeight_
    elseif self.variant_ == "button" then
        return 36
    else
        return 36
    end
end

function FileUpload:CalculateTotalHeight()
    local baseHeight = self.baseHeight_ or self:GetBaseHeight()
    local fileListHeight = 0

    if self.showFileList_ and #self.files_ > 0 then
        -- Add spacing between dropzone/button and file list
        local listOffset = self.variant_ == "dropzone" and 20 or 8
        fileListHeight = listOffset + #self.files_ * self.fileItemHeight_
    end

    return baseHeight + fileListHeight
end

function FileUpload:UpdateTotalHeight()
    local height = self:CalculateTotalHeight()
    self:SetStyle({ height = height })  -- SetStyle auto-triggers layout dirty
end

-- ============================================================================
-- File Management
-- ============================================================================

function FileUpload:GetFiles()
    return self.files_
end

function FileUpload:AddFile(file)
    -- Validate file
    if self.maxSize_ and file.size > self.maxSize_ then
        if self.onError_ then
            self.onError_(self, "File too large: " .. file.name)
        end
        return false
    end

    if not self.multiple_ and #self.files_ > 0 then
        self.files_ = {}
    end

    if #self.files_ >= self.maxFiles_ then
        if self.onError_ then
            self.onError_(self, "Maximum files reached")
        end
        return false
    end

    file.status = file.status or "pending"
    file.progress = file.progress or 0
    table.insert(self.files_, file)

    -- Update height to accommodate file list
    self:UpdateTotalHeight()

    if self.onFileSelect_ then
        self.onFileSelect_(self, file)
    end

    return true
end

function FileUpload:RemoveFile(index)
    local file = self.files_[index]
    if file then
        table.remove(self.files_, index)

        -- Update height after removing file
        self:UpdateTotalHeight()

        if self.onFileRemove_ then
            self.onFileRemove_(self, file)
        end
    end
end

function FileUpload:ClearFiles()
    self.files_ = {}
    -- Update height after clearing all files
    self:UpdateTotalHeight()
end

function FileUpload:SetFileProgress(index, progress)
    if self.files_[index] then
        self.files_[index].progress = progress
        self.files_[index].status = progress >= 1 and "complete" or "uploading"

        if self.onUploadProgress_ then
            self.onUploadProgress_(self, self.files_[index], progress)
        end

        if progress >= 1 and self.onUploadComplete_ then
            self.onUploadComplete_(self, self.files_[index])
        end
    end
end

function FileUpload:SetFileError(index, error)
    if self.files_[index] then
        self.files_[index].status = "error"
        self.files_[index].error = error
    end
end

-- ============================================================================
-- Drag State
-- ============================================================================

function FileUpload:SetDragging(dragging)
    self.isDragging_ = dragging
end

-- ============================================================================
-- Helpers
-- ============================================================================

function FileUpload:FormatFileSize(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    else
        return string.format("%.1f GB", bytes / (1024 * 1024 * 1024))
    end
end

function FileUpload:GetFileIcon(fileType)
    if fileType:match("^image/") then
        return "🖼️"
    elseif fileType:match("^video/") then
        return "🎬"
    elseif fileType:match("^audio/") then
        return "🎵"
    elseif fileType:match("pdf") then
        return "📄"
    elseif fileType:match("zip") or fileType:match("rar") or fileType:match("7z") then
        return "📦"
    else
        return "📁"
    end
end

-- ============================================================================
-- Render
-- ============================================================================

function FileUpload:Render(nvg)
    local x, y = self:GetAbsolutePosition()
    local w, h = self:GetComputedSize()
    local theme = Theme.GetTheme()

    Widget.Render(self, nvg)

    if self.variant_ == "dropzone" then
        self:RenderDropzone(nvg, x, y, w, h)
    elseif self.variant_ == "button" then
        self:RenderButton(nvg, x, y, w, h)
    else
        self:RenderInline(nvg, x, y, w, h)
    end

    -- Render file list
    if self.showFileList_ and #self.files_ > 0 then
        local baseHeight = self.baseHeight_ or self:GetBaseHeight()
        local listOffset = self.variant_ == "dropzone" and 20 or 8
        local listY = y + baseHeight + listOffset
        self:RenderFileList(nvg, x, listY, w)
    end
end

function FileUpload:RenderDropzone(nvg, x, y, w, h)
    local props = self.props
    local borderRadius = props.borderRadius or 8
    local headerH = self.headerHeight_
    local dropzoneH = self.dropzoneHeight_
    local totalH = headerH + dropzoneH

    -- Container background
    local containerBg = self.disabled_
        and Theme.Color("disabled")
        or (props.backgroundColor or Theme.Color("surface"))
    local containerRect = { x = x, y = y, w = w, h = totalH }
    self:CreateShapePath(nvg, self:GetShapeGeometry(containerRect, nil, borderRadius))
    nvgFillColor(nvg, nvgRGBA(containerBg[1], containerBg[2], containerBg[3], containerBg[4] or 255))
    nvgFill(nvg)

    -- Container border
    local borderWidth = props.borderWidth or 0
    local baseBorderColor = props.borderColor or Theme.Color("border")
    local containerBorderColor = baseBorderColor
    if not self.disabled_ then
        if self.isDragging_ then
            containerBorderColor = props.dropzoneDraggingBorderColor or Theme.Color("primary")
        elseif self.isHovered_ and props.dropzoneHoverBorderColor then
            containerBorderColor = props.dropzoneHoverBorderColor
        end
    end
    if borderWidth > 0 then
        self:CreateShapePath(nvg, self:GetShapeGeometry(containerRect, nil, borderRadius))
        nvgStrokeColor(nvg, nvgRGBA(containerBorderColor[1], containerBorderColor[2], containerBorderColor[3], containerBorderColor[4] or 255))
        nvgStrokeWidth(nvg, borderWidth)
        nvgStroke(nvg)
    end

    -- Header section
    local dropzoneY = y
    if self.showHeader_ then
        local headerPadX = 16
        local headerPadY = 14

        -- Header text
        nvgFontSize(nvg, Theme.FontSizeOf("small"))
        nvgFontFace(nvg, Theme.FontFace(props.fontFamily, "bold"))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, self.disabled_ and Theme.NvgColor("textDisabled") or Theme.NvgColor("text"))
        nvgText(nvg, x + headerPadX, y + headerH / 2, self.headerText_)

        -- Header bottom border
        local borderColor = baseBorderColor
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x, y + headerH)
        nvgLineTo(nvg, x + w, y + headerH)
        nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        dropzoneY = y + headerH
    end

    -- Bounds for hit testing: only the actual drop zone area, not the header
    self.dropzoneBounds_ = { x = x, y = dropzoneY, w = w, h = dropzoneH }

    -- Drop zone background (bottom corners match container, top is flat when header present)
    local dropzoneRadius = self.showHeader_ and Widget.BottomRadius(borderRadius) or borderRadius
    local dropzoneRect = { x = x, y = dropzoneY, w = w, h = dropzoneH }
    local dzBgColor = props.dropzoneBgColor
    if dzBgColor then
        self:CreateShapePath(nvg, self:GetShapeGeometry(dropzoneRect, nil, dropzoneRadius))
        nvgFillColor(nvg, nvgRGBA(dzBgColor[1], dzBgColor[2], dzBgColor[3], dzBgColor[4] or 255))
        nvgFill(nvg)
    end

    -- Hover/drag overlay on drop zone
    if not self.disabled_ then
        if self.isDragging_ then
            local primaryColor = Theme.Color("primary")
            self:CreateShapePath(nvg, self:GetShapeGeometry(dropzoneRect, nil, dropzoneRadius))
            nvgFillColor(nvg, nvgRGBA(primaryColor[1], primaryColor[2], primaryColor[3], 30))
            nvgFill(nvg)
        elseif self.isHovered_ then
            self:CreateShapePath(nvg, self:GetShapeGeometry(dropzoneRect, nil, dropzoneRadius))
            nvgFillColor(nvg, Theme.NvgColor("surfaceHover"))
            nvgFill(nvg)
        end
    end

    -- Drop zone border (solid or dashed)
    local dzBorderStyle = props.dropzoneBorderStyle or "dashed"
    local dzBorderWidth = props.dropzoneBorderWidth ~= nil and props.dropzoneBorderWidth or 2
    local explicitDropzoneBorderWidth = props.dropzoneBorderWidth ~= nil
    if dzBorderStyle ~= "none" and dzBorderWidth > 0 and (borderWidth == 0 or explicitDropzoneBorderWidth) then
        local dzBorderColor = props.dropzoneBorderColor or baseBorderColor
        if not self.disabled_ then
            if self.isDragging_ then
                dzBorderColor = props.dropzoneDraggingBorderColor or Theme.Color("primary")
            elseif self.isHovered_ and props.dropzoneHoverBorderColor then
                dzBorderColor = props.dropzoneHoverBorderColor
            end
        end
        self:CreateShapePath(nvg, self:GetShapeGeometry(dropzoneRect, nil, dropzoneRadius))
        nvgStrokeColor(nvg, nvgRGBA(dzBorderColor[1], dzBorderColor[2], dzBorderColor[3], dzBorderColor[4] or 255))
        nvgStrokeWidth(nvg, dzBorderWidth)
        nvgStroke(nvg)
    end

    -- Icon with optional wrapper
    local dzCenterY = dropzoneY + dropzoneH / 2
    local iconWrapSize = props.iconSize or 46
    local iconBgColor = props.iconBgColor
    local iconRadius = props.iconRadius or 12

    local iconCenterY = dzCenterY - 16  -- shift up to make room for label/hint

    if iconBgColor then
        -- Draw icon wrapper background
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x + w / 2 - iconWrapSize / 2, iconCenterY - iconWrapSize / 2, iconWrapSize, iconWrapSize, iconRadius)
        nvgFillColor(nvg, nvgRGBA(iconBgColor[1], iconBgColor[2], iconBgColor[3], iconBgColor[4] or 255))
        nvgFill(nvg)
    end

    -- Icon text
    local iconFontSize = iconBgColor and (iconWrapSize * 0.5) or Theme.FontSizeOf("display")
    nvgFontSize(nvg, iconFontSize)
    nvgFontFace(nvg, Theme.FontFace(props.fontFamily, props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    local iconColor = props.iconColor or Theme.Color("textSecondary")
    nvgFillColor(nvg, self.disabled_ and Theme.NvgColor("textDisabled") or nvgRGBA(iconColor[1], iconColor[2], iconColor[3], iconColor[4] or 255))
    nvgText(nvg, x + w / 2, iconCenterY, self.icon_)

    -- Label
    local labelY = iconBgColor and (iconCenterY + iconWrapSize / 2 + 12) or (dzCenterY + 10)
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFontFace(nvg, Theme.FontFace(props.fontFamily, props.labelFontWeight or props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    local labelTextColor = props.labelTextColor or Theme.Color("text")
    nvgFillColor(nvg, self.disabled_ and Theme.NvgColor("textDisabled") or nvgRGBA(labelTextColor[1], labelTextColor[2], labelTextColor[3], labelTextColor[4] or 255))
    nvgText(nvg, x + w / 2, labelY, self.label_)

    -- Hint
    if self.hint_ then
        nvgFontSize(nvg, Theme.FontSizeOf("small"))
        local hintTextColor = props.hintTextColor or Theme.Color("textSecondary")
        nvgFillColor(nvg, nvgRGBA(hintTextColor[1], hintTextColor[2], hintTextColor[3], hintTextColor[4] or 255))
        nvgText(nvg, x + w / 2, labelY + 18, self.hint_)
    end
end

function FileUpload:RenderButton(nvg, x, y, w, h)
    local theme = Theme.GetTheme()
    local btnH = 36

    self.buttonBounds_ = { x = x, y = y, w = w, h = btnH }

    -- Button background
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, btnH, 4)

    if self.disabled_ then
        nvgFillColor(nvg, Theme.NvgColor("disabled"))
    elseif self.isHovered_ then
        nvgFillColor(nvg, Theme.NvgColor("primaryHover"))
    else
        nvgFillColor(nvg, Theme.NvgColor("primary"))
    end
    nvgFill(nvg)

    -- Button text
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
    local labelTextColor = self.props.labelTextColor
    if self.disabled_ then
        nvgFillColor(nvg, Theme.NvgColor("textDisabled"))
    elseif labelTextColor then
        nvgFillColor(nvg, nvgRGBA(labelTextColor[1], labelTextColor[2], labelTextColor[3], labelTextColor[4] or 255))
    else
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
    end
    nvgText(nvg, x + w / 2, y + btnH / 2, self.label_)
end

function FileUpload:RenderInline(nvg, x, y, w, h)
    local theme = Theme.GetTheme()
    local inlineH = 36

    self.inlineBounds_ = { x = x, y = y, w = w, h = inlineH }

    -- Icon
    nvgFontSize(nvg, Theme.FontSizeOf("subtitle"))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
    nvgText(nvg, x, y + inlineH / 2, self.icon_)

    -- Label
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))

    local labelTextColor = self.props.labelTextColor
    if self.isHovered_ and not labelTextColor then
        nvgFillColor(nvg, Theme.NvgColor("primary"))
    elseif labelTextColor then
        nvgFillColor(nvg, nvgRGBA(labelTextColor[1], labelTextColor[2], labelTextColor[3], labelTextColor[4] or 255))
    else
        nvgFillColor(nvg, Theme.NvgColor("text"))
    end
    nvgText(nvg, x + 28, y + inlineH / 2, self.label_)
end

function FileUpload:RenderFileList(nvg, x, y, w)
    local theme = Theme.GetTheme()
    local fileItemHeight = self.fileItemHeight_

    self.fileItemBounds_ = {}

    for i, file in ipairs(self.files_) do
        local itemY = y + (i - 1) * fileItemHeight

        self.fileItemBounds_[i] = { x = x, y = itemY, w = w, h = fileItemHeight }

        -- Item background
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x, itemY, w, fileItemHeight - 4, 4)
        nvgFillColor(nvg, Theme.NvgColor("surfaceAlt"))
        nvgFill(nvg)

        -- File icon
        local icon = self:GetFileIcon(file.type or "")
        nvgFontSize(nvg, Theme.FontSizeOf("title"))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
        nvgText(nvg, x + 20, itemY + fileItemHeight / 2, icon)

        -- File name
        nvgFontSize(nvg, Theme.FontSizeOf("bodySmall"))
        nvgFontFace(nvg, Theme.FontFace(self.props.fontFamily, self.props.fontWeight))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Theme.NvgColor("text"))
        nvgText(nvg, x + 44, itemY + fileItemHeight / 2 - 8, file.name)

        -- File size
        nvgFontSize(nvg, Theme.FontSizeOf("caption"))
        nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
        nvgText(nvg, x + 44, itemY + fileItemHeight / 2 + 8, self:FormatFileSize(file.size or 0))

        -- Status indicator
        local statusX = x + w - 60
        if file.status == "complete" then
            nvgFillColor(nvg, Theme.NvgColor("success"))
            nvgText(nvg, statusX, itemY + fileItemHeight / 2, "✓ Done")
        elseif file.status == "error" then
            nvgFillColor(nvg, Theme.NvgColor("error"))
            nvgText(nvg, statusX, itemY + fileItemHeight / 2, "✗ Error")
        elseif file.status == "uploading" and self.showProgress_ then
            -- Progress bar
            local progressW = 50
            local progressH = 4
            local progressY = itemY + fileItemHeight / 2 - progressH / 2

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, statusX, progressY, progressW, progressH, 2)
            nvgFillColor(nvg, Theme.NvgColor("border"))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, statusX, progressY, progressW * file.progress, progressH, 2)
            nvgFillColor(nvg, Theme.NvgColor("primary"))
            nvgFill(nvg)
        end

        -- Remove button
        local removeBtnX = x + w - 24
        self.removeButtonBounds_ = self.removeButtonBounds_ or {}
        self.removeButtonBounds_[i] = { x = removeBtnX, y = itemY + 12, w = 20, h = 20 }

        nvgFontSize(nvg, Theme.FontSizeOf("body"))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, Theme.NvgColor("textSecondary"))
        nvgText(nvg, removeBtnX + 10, itemY + fileItemHeight / 2, "✕")
    end
end

-- ============================================================================
-- Input Handling
-- ============================================================================

function FileUpload:PointInBounds(px, py, bounds)
    if not bounds then return false end
    return px >= bounds.x and px <= bounds.x + bounds.w and
           py >= bounds.y and py <= bounds.y + bounds.h
end

function FileUpload:OnPointerMove(event)
    if not event then return end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    local bounds = self.dropzoneBounds_ or self.buttonBounds_ or self.inlineBounds_
    self.isHovered_ = self:PointInBounds(px, py, bounds)
end

function FileUpload:OnMouseLeave()
    self.isHovered_ = false
    self.isDragging_ = false
end

function FileUpload:OnClick(event)
    if not event then return end
    if self.disabled_ then return false end

    -- Get offset between render coords and screen coords
    local renderX, renderY = self:GetAbsolutePosition()
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local offsetX = renderX - hitTest.x
    local offsetY = renderY - hitTest.y
    local px = event.x + offsetX
    local py = event.y + offsetY

    -- Check remove buttons
    if self.removeButtonBounds_ then
        for i, bounds in pairs(self.removeButtonBounds_) do
            if self:PointInBounds(px, py, bounds) then
                self:RemoveFile(i)
                return true
            end
        end
    end

    -- Check main interaction area
    local bounds = self.dropzoneBounds_ or self.buttonBounds_ or self.inlineBounds_
    if self:PointInBounds(px, py, bounds) then
        -- In a real implementation, this would trigger a file dialog
        -- For now, we simulate adding a file
        self:AddFile({
            name = "sample_file_" .. (#self.files_ + 1) .. ".txt",
            size = math.random(1000, 5000000),
            type = "text/plain",
        })
        return true
    end

    return false
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create a dropzone file upload
---@param props table|nil
---@return FileUpload
function FileUpload.Dropzone(props)
    props = props or {}
    props.variant = "dropzone"
    return FileUpload(props)
end

--- Create a button file upload
---@param props table|nil
---@return FileUpload
function FileUpload.Button(props)
    props = props or {}
    props.variant = "button"
    props.label = props.label or "Choose File"
    return FileUpload(props)
end

--- Create an image upload
---@param props table|nil
---@return FileUpload
function FileUpload.Image(props)
    props = props or {}
    props.accept = "image/*"
    props.icon = "🖼️"
    props.label = props.label or "Drop images here or click to upload"
    props.hint = props.hint or "Supports: JPG, PNG, GIF"
    return FileUpload(props)
end

--- Create a multi-file upload
---@param props table|nil
---@return FileUpload
function FileUpload.Multiple(props)
    props = props or {}
    props.multiple = true
    return FileUpload(props)
end

--- Create a document upload
---@param props table|nil
---@return FileUpload
function FileUpload.Document(props)
    props = props or {}
    props.accept = ".pdf,.doc,.docx,.txt"
    props.icon = "📄"
    props.label = props.label or "Drop documents here or click to upload"
    props.hint = props.hint or "Supports: PDF, DOC, DOCX, TXT"
    return FileUpload(props)
end

return FileUpload
