-- ============================================================================
-- Stepper Widget
-- UrhoX UI Library - Yoga + NanoVG
-- Step-by-step progress indicator
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Theme = require("urhox-libs/UI/Core/Theme")
local Style = require("urhox-libs/UI/Core/Style")
local UI = require("urhox-libs/UI/Core/UI")

---@class StepItem
---@field id? string|number Optional step identifier
---@field label string Step label
---@field description? string Optional description
---@field icon? string Custom icon (instead of number)
---@field optional? boolean Is step optional
---@field error? boolean Is step in error state
---@field disabled? boolean Is step disabled

---@class StepperProps : WidgetProps
---@field steps? StepItem[] Step items
---@field activeStep? number Current active step, 0-indexed (default: 0)
---@field orientation? string "horizontal" | "vertical" (default: "horizontal")
---@field variant? string "default" | "dots" | "simple" (default: "default")
---@field size? string "sm" | "md" | "lg" (default: "md")
---@field clickable? boolean Allow clicking on steps
---@field showConnector? boolean Show connector lines (default: true)
---@field completedBgColor? RGBAColor|string Completed step icon background color
---@field completedBorderColor? RGBAColor|string Completed step icon border color
---@field completedTextColor? RGBAColor|string Completed step icon text color
---@field completedBoxShadow? table|false Completed step icon shadow
---@field activeBgColor? RGBAColor|string Active step icon background color
---@field activeBorderColor? RGBAColor|string Active step icon border color
---@field activeTextColor? RGBAColor|string Active step icon text color
---@field activeBoxShadow? table|false Active step icon shadow
---@field activeIconSize? number Active step icon size override
---@field activeIconOffsetX? number Active step icon horizontal render offset
---@field activeIconOffsetY? number Active step icon vertical render offset
---@field pendingBgColor? RGBAColor|string Pending step icon background color
---@field pendingBorderColor? RGBAColor|string Pending step icon border color
---@field pendingTextColor? RGBAColor|string Pending step icon text color
---@field pendingBoxShadow? table|false Pending step icon shadow
---@field errorBgColor? RGBAColor|string Error step icon background color
---@field errorBorderColor? RGBAColor|string Error step icon border color
---@field errorTextColor? RGBAColor|string Error step icon text color
---@field errorBoxShadow? table|false Error step icon shadow
---@field connectorColor? RGBAColor|string Connector line color
---@field completedConnectorColor? RGBAColor|string Completed connector line color
---@field pendingConnectorColor? RGBAColor|string Pending connector line color
---@field connectorWidth? number Connector line width
---@field alternativeLabel? boolean Labels below icons (horizontal only)
---@field onChange? fun(self: Stepper, step: number) Step change callback

---@class Stepper : Widget
---@overload fun(props?: StepperProps): Stepper
---@field props StepperProps
---@field new fun(self, props?: StepperProps): Stepper
local Stepper = Widget:Extend("Stepper")

-- Size presets
local SIZE_PRESETS = {
    sm = { iconSize = 24, fontSize = 12, descSize = 10, spacing = 8 },
    md = { iconSize = 32, fontSize = 14, descSize = 12, spacing = 12 },
    lg = { iconSize = 40, fontSize = 16, descSize = 14, spacing = 16 },
}

-- ============================================================================
-- Constructor
-- ============================================================================

---@param props StepperProps?
function Stepper:Init(props)
    props = props or {}

    -- Theme integration
    local themeStyle = Theme.ComponentStyle("Stepper")
    Style.ApplyDefaults(props, themeStyle)

    -- Default settings
    self.steps_ = props.steps or {}
    self.activeStep_ = props.activeStep or 0
    self.orientation_ = props.orientation or "horizontal"
    self.variant_ = props.variant or "default"
    self.size_ = props.size or "md"
    self.clickable_ = props.clickable or false
    self.showConnector_ = props.showConnector ~= false
    self.alternativeLabel_ = props.alternativeLabel or false
    self.onChange_ = props.onChange

    -- State
    self.hoveredStep_ = nil

    -- Call parent constructor
    Widget.Init(self, props)

    -- Calculate and set height after parent init
    self:UpdateHeight()
end

-- ============================================================================
-- Height Calculation
-- ============================================================================

function Stepper:CalculateTotalHeight()
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    local iconSize = sizePreset.iconSize
    local spacing = sizePreset.spacing
    local fontSize = sizePreset.fontSize
    local descSize = sizePreset.descSize

    if self.orientation_ == "horizontal" then
        -- Height includes icon + label space
        local iconTop, iconBottom = self:GetIconVerticalMetrics(iconSize)
        local iconVisualHeight = iconBottom - iconTop
        local height = iconVisualHeight + spacing * 2

        -- Check if any step has description (labels to the right need more height)
        local hasDescription = false
        for _, step in ipairs(self.steps_) do
            if step.description then
                hasDescription = true
                break
            end
        end

        if hasDescription then
            -- Description renders below label, need extra height
            height = height + descSize + 4
        end

        if self.alternativeLabel_ then
            height = height + fontSize + spacing
        end

        return height
    else
        -- Vertical orientation
        local stepCount = #self.steps_
        if stepCount == 0 then return iconSize + spacing * 2 end

        local iconTop, iconBottom = self:GetIconVerticalMetrics(iconSize)
        local iconVisualHeight = iconBottom - iconTop
        local stepHeight = iconVisualHeight + spacing * 3
        -- Add extra height for description
        if self.variant_ == "default" then
            stepHeight = stepHeight + 20
        end

        return stepCount * stepHeight
    end
end

function Stepper:UpdateHeight()
    local height = self:CalculateTotalHeight()
    self:SetStyle({ height = height })  -- SetStyle auto-triggers layout dirty
end

function Stepper:GetIconVerticalMetrics(baseIconSize)
    local activeSize = self.props.activeIconSize or baseIconSize
    local activeOffsetY = self.props.activeIconOffsetY or 0
    local top = math.min(0, activeOffsetY)
    local bottom = math.max(baseIconSize, activeOffsetY + activeSize)
    return top, bottom
end

function Stepper:GetStateIconGeometry(x, y, baseIconSize, stepState)
    if stepState ~= "active" then
        return x, y, baseIconSize
    end

    local iconSize = self.props.activeIconSize or baseIconSize
    local offsetX = self.props.activeIconOffsetX or 0
    local offsetY = self.props.activeIconOffsetY or 0
    return x + offsetX, y + offsetY, iconSize
end

-- ============================================================================
-- Rendering
-- ============================================================================

function Stepper:Render(nvg)
    local l = self:GetAbsoluteLayout()

    if self.orientation_ == "horizontal" then
        self:RenderHorizontal(nvg, l)
    else
        self:RenderVertical(nvg, l)
    end
end

--- Render horizontal stepper
function Stepper:RenderHorizontal(nvg, l)
    local steps = self.steps_
    local activeStep = self.activeStep_
    local variant = self.variant_
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md

    local stepCount = #steps
    if stepCount == 0 then return end

    local iconSize = sizePreset.iconSize
    local spacing = sizePreset.spacing
    local iconTop = self:GetIconVerticalMetrics(iconSize)
    local iconBaseY = l.y - iconTop

    -- Calculate step width - reserve space for last step's label
    local lastStepLabelWidth = 0
    if stepCount > 0 and variant ~= "dots" and not self.alternativeLabel_ then
        lastStepLabelWidth = self:EstimateLabelWidth(steps[stepCount], sizePreset) + spacing
    end
    local availableWidth = l.w - iconSize - lastStepLabelWidth
    local stepWidth = stepCount > 1 and (availableWidth / (stepCount - 1)) or l.w

    for i, step in ipairs(steps) do
        local stepIndex = i - 1
        local x = l.x + stepIndex * stepWidth
        local y = iconBaseY

        local stepState = self:GetStepState(stepIndex, activeStep, step)
        local isHovered = self.hoveredStep_ == stepIndex

        if self.alternativeLabel_ then
            -- Icon centered, label below
            local centerX = x + (i == 1 and 0 or (i == stepCount and iconSize or iconSize / 2))
            local iconX, iconY, renderIconSize = self:GetStateIconGeometry(centerX, y, iconSize, stepState)
            self:RenderStepIcon(nvg, iconX, iconY, renderIconSize, stepIndex + 1, step, stepState, isHovered, variant)

            -- Label below
            self:RenderStepLabelBelow(nvg, centerX + iconSize / 2, y + iconSize + spacing, step, stepState, sizePreset)
        else
            -- Icon with label to the right
            local iconX, iconY, renderIconSize = self:GetStateIconGeometry(x, y, iconSize, stepState)
            self:RenderStepIcon(nvg, iconX, iconY, renderIconSize, stepIndex + 1, step, stepState, isHovered, variant)

            if variant ~= "dots" then
                self:RenderStepLabel(nvg, x + iconSize + spacing, y, iconSize, step, stepState, sizePreset)
            end
        end

        -- Connector line
        if self.showConnector_ and i < stepCount then
            local connectorX = x + iconSize + (self.alternativeLabel_ and -iconSize / 2 or spacing)
            local connectorWidth = stepWidth - iconSize - (self.alternativeLabel_ and 0 or spacing * 2)

            if variant ~= "dots" and not self.alternativeLabel_ then
                -- Adjust for label width
                connectorWidth = connectorWidth - self:EstimateLabelWidth(step, sizePreset) - spacing
                connectorX = connectorX + self:EstimateLabelWidth(step, sizePreset) + spacing
            end

            local nextStepState = self:GetStepState(stepIndex + 1, activeStep, steps[i + 1])
            self:RenderConnector(nvg, connectorX, y + iconSize / 2, connectorWidth, "horizontal", stepState, nextStepState)
        end
    end
end

--- Render vertical stepper
function Stepper:RenderVertical(nvg, l)
    local steps = self.steps_
    local activeStep = self.activeStep_
    local variant = self.variant_
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md

    local stepCount = #steps
    if stepCount == 0 then return end

    local iconSize = sizePreset.iconSize
    local spacing = sizePreset.spacing
    local iconTop, iconBottom = self:GetIconVerticalMetrics(iconSize)
    local iconVisualHeight = iconBottom - iconTop
    local stepHeight = iconVisualHeight + spacing * 3

    -- Add extra height for description
    if variant == "default" then
        stepHeight = stepHeight + 20
    end

    for i, step in ipairs(steps) do
        local stepIndex = i - 1
        local x = l.x
        local y = l.y + stepIndex * stepHeight - iconTop

        local stepState = self:GetStepState(stepIndex, activeStep, step)
        local isHovered = self.hoveredStep_ == stepIndex

        -- Icon
        local iconX, iconY, renderIconSize = self:GetStateIconGeometry(x, y, iconSize, stepState)
        self:RenderStepIcon(nvg, iconX, iconY, renderIconSize, stepIndex + 1, step, stepState, isHovered, variant)

        -- Label to the right
        if variant ~= "dots" then
            self:RenderStepLabel(nvg, x + iconSize + spacing, y, iconSize, step, stepState, sizePreset)
        end

        -- Connector line
        if self.showConnector_ and i < stepCount then
            local connectorY = y + iconSize + spacing / 2
            local connectorHeight = stepHeight - iconSize - spacing

            local nextStepState = self:GetStepState(stepIndex + 1, activeStep, steps[i + 1])
            self:RenderConnector(nvg, x + iconSize / 2, connectorY, connectorHeight, "vertical", stepState, nextStepState)
        end
    end
end

--- Get step state
function Stepper:GetStepState(stepIndex, activeStep, step)
    if step.error then
        return "error"
    elseif stepIndex < activeStep then
        return "completed"
    elseif stepIndex == activeStep then
        return "active"
    else
        return "pending"
    end
end

--- Render step icon
function Stepper:RenderStepIcon(nvg, x, y, size, number, step, stepState, isHovered, variant)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local strokeWidth = self.props.borderWidth or 2

    local bgColor, borderColor, textColor, iconContent

    -- Determine colors based on state
    local activeColor = self.props.activeBgColor or Theme.Color("primary")
    local activeText = self.props.activeTextColor or { 255, 255, 255, 255 }
    if stepState == "completed" then
        bgColor = self.props.completedBgColor or activeColor
        borderColor = self.props.completedBorderColor or bgColor
        textColor = self.props.completedTextColor or activeText
        iconContent = "✓"
    elseif stepState == "active" then
        bgColor = activeColor
        borderColor = self.props.activeBorderColor or bgColor
        textColor = activeText
        iconContent = step.icon or tostring(number)
    elseif stepState == "error" then
        bgColor = self.props.errorBgColor or Theme.Color("error")
        borderColor = self.props.errorBorderColor or bgColor
        textColor = self.props.errorTextColor or activeText
        iconContent = "!"
    else -- pending
        bgColor = self.props.pendingBgColor or Theme.Color("background")
        borderColor = self.props.pendingBorderColor or Theme.Color("border")
        textColor = self.props.pendingTextColor or Theme.Color("textSecondary")
        iconContent = step.icon or tostring(number)
    end

    -- Hover effect
    if isHovered and self.clickable_ then
        if stepState == "pending" then
            bgColor = Theme.Color("surface")
        end
        -- State token: highlight border on hover
        local hoverBorderColor = self.props.hoverBorderColor
        if hoverBorderColor then
            borderColor = hoverBorderColor
        end
    end

    local cx = x + size / 2
    local cy = y + size / 2

    local radius = self.props.borderRadius ~= nil and self.props.borderRadius or (size / 2)
    local boxShadow = self.props[stepState .. "BoxShadow"]
    local hasExplicitStateBorder = self.props[stepState .. "BorderColor"] ~= nil
    local shouldStrokeBorder = stepState == "pending" or hasExplicitStateBorder

    if variant == "dots" then
        -- Simple dot variant
        local dotSize = size * 0.4
        local dotRadius = self.props.borderRadius ~= nil and self.props.borderRadius or (dotSize / 2)
        if boxShadow and boxShadow ~= false then
            local geom = self:GetShapeGeometry({
                x = cx - dotSize / 2,
                y = cy - dotSize / 2,
                w = dotSize,
                h = dotSize,
            }, nil, dotRadius)
            self:RenderBoxShadows(nvg, geom, boxShadow)
        end
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - dotSize / 2, cy - dotSize / 2, dotSize, dotSize, dotRadius)
        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
        nvgFill(nvg)

        if shouldStrokeBorder then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx - dotSize / 2, cy - dotSize / 2, dotSize, dotSize, dotRadius)
            nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
            nvgStrokeWidth(nvg, strokeWidth)
            nvgStroke(nvg)
        end
    else
        -- Circle with number/icon
        if boxShadow and boxShadow ~= false then
            local geom = self:GetShapeGeometry({
                x = cx - size / 2,
                y = cy - size / 2,
                w = size,
                h = size,
            }, nil, radius)
            self:RenderBoxShadows(nvg, geom, boxShadow)
        end
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, cx - size / 2, cy - size / 2, size, size, radius)

        nvgFillColor(nvg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
        nvgFill(nvg)

        if shouldStrokeBorder then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx - size / 2 + 1, cy - size / 2 + 1, size - 2, size - 2, math.max(0, radius - 1))
            nvgStrokeColor(nvg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
            nvgStrokeWidth(nvg, strokeWidth)
            nvgStroke(nvg)
        end

        -- Icon/number text
        nvgFontFace(nvg, fontFamily)
        nvgFontSize(nvg, size * 0.45)
        nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
        nvgText(nvg, cx, cy, iconContent, nil)
    end
end

--- Render step label (to the right of icon)
function Stepper:RenderStepLabel(nvg, x, y, iconSize, step, stepState, sizePreset)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local fontSize = Theme.FontSize(sizePreset.fontSize)
    local descSize = Theme.FontSize(sizePreset.descSize)
    local gap = 2

    local textColor = stepState == "pending" and Theme.Color("textSecondary") or Theme.Color("text")
    local descColor = Theme.Color("textSecondary")

    if stepState == "error" then
        textColor = Theme.Color("error")
    end

    local labelY = y + iconSize / 2

    -- If has description, adjust Y
    if step.description then
        labelY = y + iconSize / 2 - fontSize / 2
    end

    -- Label
    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, fontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local labelText = step.label
    if step.optional then
        labelText = labelText .. " (Optional)"
    end
    nvgText(nvg, x, labelY, labelText, nil)

    -- Description
    if step.description then
        nvgFontSize(nvg, descSize)
        nvgFillColor(nvg, nvgRGBA(descColor[1], descColor[2], descColor[3], descColor[4] or 255))
        nvgText(nvg, x, labelY + fontSize + gap, step.description, nil)
    end
end

--- Render step label below icon (alternative layout)
function Stepper:RenderStepLabelBelow(nvg, x, y, step, stepState, sizePreset)
    local fontFamily = Theme.FontFace(self.props.fontFamily, self.props.fontWeight)
    local fontSize = Theme.FontSize(sizePreset.fontSize)
    local descSize = Theme.FontSize(sizePreset.descSize)
    local gap = 2

    local textColor = stepState == "pending" and Theme.Color("textSecondary") or Theme.Color("text")
    local descColor = Theme.Color("textSecondary")

    if stepState == "error" then
        textColor = Theme.Color("error")
    end

    -- Label (centered)
    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, fontSize)
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_TOP)

    local labelText = step.label
    if step.optional then
        labelText = labelText .. " (Optional)"
    end
    nvgText(nvg, x, y, labelText, nil)

    -- Description
    if step.description then
        nvgFontSize(nvg, descSize)
        nvgFillColor(nvg, nvgRGBA(descColor[1], descColor[2], descColor[3], descColor[4] or 255))
        nvgText(nvg, x, y + fontSize + gap, step.description, nil)
    end
end

--- Render connector line
function Stepper:RenderConnector(nvg, x, y, length, orientation, currentState, nextState)
    local completedColor = self.props.completedConnectorColor
        or self.props.connectorColor
        or self.props.activeBgColor
        or Theme.Color("primary")
    local pendingColor = self.props.pendingConnectorColor
        or self.props.connectorColor
        or Theme.Color("border")
    local strokeWidth = self.props.connectorWidth or self.props.borderWidth or 2

    -- Determine if connector should be completed
    local isCompleted = currentState == "completed"
    local color = isCompleted and completedColor or pendingColor

    nvgBeginPath(nvg)

    if orientation == "horizontal" then
        nvgMoveTo(nvg, x, y)
        nvgLineTo(nvg, x + length, y)
    else
        nvgMoveTo(nvg, x, y)
        nvgLineTo(nvg, x, y + length)
    end

    nvgStrokeColor(nvg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(nvg, strokeWidth)
    nvgStroke(nvg)
end

--- Estimate label width
function Stepper:EstimateLabelWidth(step, sizePreset)
    local labelText = step.label
    if step.optional then
        labelText = labelText .. " (Optional)"
    end
    -- Rough estimate: fontSize * 0.6 per character
    return #labelText * sizePreset.fontSize * 0.6
end

-- ============================================================================
-- Hit Testing
-- ============================================================================

--- Find step at position
function Stepper:FindStepAt(screenX, screenY)
    local l = self:GetAbsoluteLayout()
    local steps = self.steps_
    local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
    local iconSize = sizePreset.iconSize
    local iconTop, iconBottom = self:GetIconVerticalMetrics(iconSize)
    local iconVisualHeight = iconBottom - iconTop

    -- Convert screen coords to render coords
    local hitTest = self:GetAbsoluteLayoutForHitTest()
    local x = screenX + (l.x - hitTest.x)
    local y = screenY + (l.y - hitTest.y)

    if self.orientation_ == "horizontal" then
        local stepCount = #steps
        if stepCount == 0 then return nil end

        local spacing = sizePreset.spacing
        local lastStepLabelWidth = 0
        if stepCount > 0 and self.variant_ ~= "dots" and not self.alternativeLabel_ then
            lastStepLabelWidth = self:EstimateLabelWidth(steps[stepCount], sizePreset) + spacing
        end
        local availableWidth = l.w - iconSize - lastStepLabelWidth
        local stepWidth = stepCount > 1 and (availableWidth / (stepCount - 1)) or l.w
        local iconBaseY = l.y - iconTop

        for i, step in ipairs(steps) do
            local stepIndex = i - 1
            local stepX = l.x + stepIndex * stepWidth
            local stepState = self:GetStepState(stepIndex, self.activeStep_, step)
            local iconX, iconY, renderIconSize = self:GetStateIconGeometry(stepX, iconBaseY, iconSize, stepState)
            local cx = iconX + renderIconSize / 2
            local cy = iconY + renderIconSize / 2
            local dx = x - cx
            local dy = y - cy
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= renderIconSize / 2 + 4 then
                return stepIndex
            end
        end
    else
        local spacing = sizePreset.spacing
        local stepHeight = iconVisualHeight + spacing * 3
        if self.variant_ == "default" then
            stepHeight = stepHeight + 20
        end

        for i, step in ipairs(steps) do
            local stepIndex = i - 1
            local stepX = l.x
            local stepY = l.y + stepIndex * stepHeight - iconTop
            local stepState = self:GetStepState(stepIndex, self.activeStep_, step)
            local iconX, iconY, renderIconSize = self:GetStateIconGeometry(stepX, stepY, iconSize, stepState)
            local cx = iconX + renderIconSize / 2
            local cy = iconY + renderIconSize / 2
            local dx = x - cx
            local dy = y - cy
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= renderIconSize / 2 + 4 then
                return stepIndex
            end
        end
    end

    return nil
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function Stepper:OnPointerMove(event)
    if not event then return end

    if self.clickable_ then
        local step = self:FindStepAt(event.x, event.y)
        if step ~= self.hoveredStep_ then
            self.hoveredStep_ = step
        end
    end
end

function Stepper:OnMouseLeave()
    self.hoveredStep_ = nil
end

function Stepper:OnClick(event)
    if not event then return end
    if not self.clickable_ then
        return
    end

    local stepIndex = self:FindStepAt(event.x, event.y)
    if stepIndex ~= nil then
        local step = self.steps_[stepIndex + 1]
        if step and not step.disabled then
            self:SetActiveStep(stepIndex)
        end
    end
end

-- ============================================================================
-- Public Methods
-- ============================================================================

--- Set active step
---@param step number Step index (0-indexed)
---@return Stepper self
function Stepper:SetActiveStep(step)
    local oldStep = self.activeStep_
    self.activeStep_ = step

    if oldStep ~= step then
        self:DispatchEvent("change", self, step, oldStep)
        if self.onChange_ then
            self.onChange_(self, step, oldStep)
        end
    end

    return self
end

--- Get active step
---@return number
function Stepper:GetActiveStep()
    return self.activeStep_
end

--- Go to next step
---@return Stepper self
function Stepper:NextStep()
    local current = self.activeStep_
    local maxStep = #self.steps_ - 1
    if current < maxStep then
        self:SetActiveStep(current + 1)
    end
    return self
end

--- Go to previous step
---@return Stepper self
function Stepper:PrevStep()
    local current = self.activeStep_
    if current > 0 then
        self:SetActiveStep(current - 1)
    end
    return self
end

--- Reset to first step
---@return Stepper self
function Stepper:Reset()
    self:SetActiveStep(0)
    return self
end

--- Complete all steps
---@return Stepper self
function Stepper:Complete()
    self:SetActiveStep(#self.steps_)
    return self
end

--- Is first step
---@return boolean
function Stepper:IsFirstStep()
    return self.activeStep_ == 0
end

--- Is last step
---@return boolean
function Stepper:IsLastStep()
    return self.activeStep_ >= #self.steps_ - 1
end

--- Is completed
---@return boolean
function Stepper:IsCompleted()
    return self.activeStep_ >= #self.steps_
end

--- Set steps
---@param steps StepItem[]
---@return Stepper self
function Stepper:SetSteps(steps)
    self.steps_ = steps
    if self.activeStep_ >= #steps then
        self.activeStep_ = math.max(0, #steps - 1)
    end
    self:UpdateHeight()
    return self
end

--- Set step error
---@param stepIndex number
---@param hasError boolean
---@return Stepper self
function Stepper:SetStepError(stepIndex, hasError)
    local step = self.steps_[stepIndex + 1]
    if step then
        step.error = hasError
    end
    return self
end

--- Set orientation
---@param orientation string "horizontal" | "vertical"
---@return Stepper self
function Stepper:SetOrientation(orientation)
    self.orientation_ = orientation
    self:UpdateHeight()
    return self
end

--- Set variant
---@param variant string "default" | "dots" | "simple"
---@return Stepper self
function Stepper:SetVariant(variant)
    self.variant_ = variant
    self:UpdateHeight()
    return self
end

--- Set size
---@param size string "sm" | "md" | "lg"
---@return Stepper self
function Stepper:SetSize(size)
    self.size_ = size
    self:UpdateHeight()
    return self
end

--- Set clickable
---@param clickable boolean
---@return Stepper self
function Stepper:SetClickable(clickable)
    self.clickable_ = clickable
    return self
end

-- ============================================================================
-- Stateful
-- ============================================================================

function Stepper:IsStateful()
    return true
end

-- ============================================================================
-- Static Helpers
-- ============================================================================

--- Create stepper from labels
---@param labels string[] Array of step labels
---@param options table|nil Stepper options
---@return Stepper
function Stepper.FromLabels(labels, options)
    options = options or {}

    local steps = {}
    for i, label in ipairs(labels) do
        table.insert(steps, {
            id = i,
            label = label,
        })
    end

    options.steps = steps
    return Stepper(options)
end

--- Create a wizard stepper with content panels
---@param steps table[] Array of { label, [description], content }
---@param options table|nil
---@return Widget, Stepper, table
function Stepper.Wizard(steps, options)
    local Panel = require("urhox-libs/UI/Widgets/Panel")

    options = options or {}

    local stepItems = {}
    local contentPanels = {}

    for i, step in ipairs(steps) do
        table.insert(stepItems, {
            id = i,
            label = step.label,
            description = step.description,
            icon = step.icon,
            optional = step.optional,
        })

        -- Create content panel
        local panel = Panel({
            width = "100%",
            flexGrow = 1,
            padding = 16,
        })

        if step.content then
            if type(step.content) == "string" then
                local Label = require("urhox-libs/UI/Widgets/Label")
                panel:AddChild(Label({
                    text = step.content,
                    color = Theme.Color("text"),
                }))
            else
                panel:AddChild(step.content)
            end
        end

        table.insert(contentPanels, panel)
    end

    options.steps = stepItems
    local stepper = Stepper(options)

    -- Create container
    local container = Panel({
        width = options.width or "100%",
        height = options.height,
        flexDirection = "column",
        gap = 16,
    })

    container:AddChild(stepper)

    -- Content area
    local contentArea = Panel({
        width = "100%",
        flexGrow = 1,
    })
    container:AddChild(contentArea)

    -- Add first panel
    if #contentPanels > 0 then
        contentArea:AddChild(contentPanels[1])
    end

    -- Setup step change handler
    local originalOnChange = stepper.onChange_
    stepper.onChange_ = function(s, newStep, oldStep)
        -- Update visible panel
        contentArea:ClearChildren()
        if contentPanels[newStep + 1] then
            contentArea:AddChild(contentPanels[newStep + 1])
        end

        if originalOnChange then
            originalOnChange(s, newStep, oldStep)
        end
    end

    return container, stepper, contentPanels
end

--- Create checkout stepper
---@param options table|nil
---@return Stepper
function Stepper.Checkout(options)
    options = options or {}
    options.steps = {
        { id = 1, label = "Cart", icon = "C" },
        { id = 2, label = "Shipping", icon = "S" },
        { id = 3, label = "Payment", icon = "P" },
        { id = 4, label = "Confirm", icon = "✓" },
    }
    return Stepper(options)
end

return Stepper
