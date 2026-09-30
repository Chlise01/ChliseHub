-- ============================================================
-- CHLISE HUB
-- Core/UI.lua
-- ============================================================

local Players =
    game:GetService("Players")

local CoreGui =
    game:GetService("CoreGui")

local TweenService =
    game:GetService("TweenService")

local UserInputService =
    game:GetService("UserInputService")


local LocalPlayer =
    Players.LocalPlayer


local UI = {}

UI.__index = UI


-- ============================================================
-- THEME
-- ============================================================

local Theme = {

    Accent =
        Color3.fromRGB(255, 70, 85),

    AccentSoft =
        Color3.fromRGB(95, 30, 38),

    Background =
        Color3.fromRGB(8, 11, 10),

    Sidebar =
        Color3.fromRGB(6, 9, 8),

    Card =
        Color3.fromRGB(15, 19, 18),

    CardHover =
        Color3.fromRGB(20, 25, 23),

    Stroke =
        Color3.fromRGB(45, 52, 50),

    Text =
        Color3.fromRGB(245, 245, 245),

    Muted =
        Color3.fromRGB(155, 163, 160),

    Disabled =
        Color3.fromRGB(85, 92, 90)
}


-- ============================================================
-- HELPERS
-- ============================================================

local function Create(className, properties)

    local object =
        Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    return object
end


local function AddStroke(
    parent,
    color,
    transparency,
    thickness
)

    local stroke =
        Create(
            "UIStroke",
            {
                Parent = parent,
                Color = color or Theme.Stroke,
                Transparency = transparency or 0,
                Thickness = thickness or 1
            }
        )

    return stroke
end


local function PointInside(guiObject, point)

    if not guiObject
        or not guiObject.Visible
    then
        return false
    end

    local position =
        guiObject.AbsolutePosition

    local size =
        guiObject.AbsoluteSize

    return
        point.X >= position.X
        and point.X <= position.X + size.X
        and point.Y >= position.Y
        and point.Y <= position.Y + size.Y
end


-- ============================================================
-- CONTROL OBJECT
-- ============================================================

local function RegisterControl(
    window,
    id,
    control,
    save
)

    if not id then
        return
    end

    control.Save =
        save ~= false

    window.Controls[id] =
        control
end


-- ============================================================
-- WINDOW
-- ============================================================

function UI.new(config)

    config =
        config or {}

    local self =
        setmetatable({}, UI)

    self.Controls = {}

    self.Tabs = {}

    self.ActiveTab = nil

    self.ActiveDropdown = nil


    -- ========================================================
    -- DESTROY OLD UI
    -- ========================================================

    local old =
        CoreGui:FindFirstChild(
            "ChliseHub"
        )

    if old then
        old:Destroy()
    end


    -- ========================================================
    -- SCREEN GUI
    -- ========================================================

    local ScreenGui =
        Create(
            "ScreenGui",
            {
                Name = "ChliseHub",

                ResetOnSpawn = false,

                IgnoreGuiInset = false,

                ZIndexBehavior =
                    Enum.ZIndexBehavior.Sibling
            }
        )

    ScreenGui.Parent =
        CoreGui


    -- ========================================================
    -- MAIN
    -- ========================================================

    local Main =
        Create(
            "Frame",
            {
                Name = "Main",

                Parent = ScreenGui,

                AnchorPoint =
                    Vector2.new(0.5, 0.5),

                Position =
                    UDim2.new(
                        0.5,
                        0,
                        0.5,
                        0
                    ),

                Size =
                    UDim2.new(
                        0,
                        config.Width or 500,
                        0,
                        config.Height or 305
                    ),

                BackgroundColor3 =
                    Theme.Background,

                BorderSizePixel = 0,

                ClipsDescendants = true
            }
        )


    Create(
        "UICorner",
        {
            Parent = Main,

            CornerRadius =
                UDim.new(0, 12)
        }
    )


    AddStroke(
        Main,
        Theme.Accent,
        0.1,
        1
    )


    -- ========================================================
    -- MOBILE SCALE
    -- ========================================================

    local UIScale =
        Create(
            "UIScale",
            {
                Parent = Main,
                Scale = 1
            }
        )


    local function UpdateScale()

        local camera =
            workspace.CurrentCamera

        if not camera then
            return
        end

        local viewport =
            camera.ViewportSize

        local scale =
            math.min(
                1,
                viewport.X / 540,
                viewport.Y / 360
            )

        UIScale.Scale =
            math.max(
                0.68,
                scale
            )
    end


    UpdateScale()


    if workspace.CurrentCamera then

        workspace.CurrentCamera
            :GetPropertyChangedSignal(
                "ViewportSize"
            )
            :Connect(
                UpdateScale
            )
    end


    -- ========================================================
    -- TOPBAR
    -- ========================================================

    local Topbar =
        Create(
            "Frame",
            {
                Parent = Main,

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        45
                    ),

                BackgroundColor3 =
                    Theme.Background,

                BorderSizePixel = 0
            }
        )


    local Title =
        Create(
            "TextLabel",
            {
                Parent = Topbar,

                BackgroundTransparency = 1,

                Position =
                    UDim2.new(
                        0,
                        13,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        1,
                        -55,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text =
                    config.Title
                    or "CHLISE HUB",

                TextColor3 =
                    Theme.Text,

                TextSize = 18,

                TextXAlignment =
                    Enum.TextXAlignment.Left
            }
        )


    local Close =
        Create(
            "TextButton",
            {
                Parent = Topbar,

                Position =
                    UDim2.new(
                        1,
                        -40,
                        0,
                        7
                    ),

                Size =
                    UDim2.new(
                        0,
                        30,
                        0,
                        30
                    ),

                BackgroundTransparency = 1,

                Text = "×",

                TextColor3 =
                    Theme.Muted,

                Font =
                    Enum.Font.GothamBold,

                TextSize = 22,

                AutoButtonColor = false
            }
        )


    Close.MouseButton1Click
        :Connect(
            function()

                ScreenGui.Enabled =
                    false
            end
        )


    local AccentLine =
        Create(
            "Frame",
            {
                Parent = Main,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0,
                        44
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        2
                    ),

                BackgroundColor3 =
                    Theme.Accent,

                BorderSizePixel = 0
            }
        )


    -- ========================================================
    -- SIDEBAR
    -- ========================================================

    local Sidebar =
        Create(
            "Frame",
            {
                Parent = Main,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0,
                        46
                    ),

                Size =
                    UDim2.new(
                        0,
                        52,
                        1,
                        -46
                    ),

                BackgroundColor3 =
                    Theme.Sidebar,

                BorderSizePixel = 0
            }
        )


    Create(
        "UIPadding",
        {
            Parent = Sidebar,

            PaddingTop =
                UDim.new(0, 8),

            PaddingBottom =
                UDim.new(0, 8)
        }
    )


    Create(
        "UIListLayout",
        {
            Parent = Sidebar,

            FillDirection =
                Enum.FillDirection.Vertical,

            SortOrder =
                Enum.SortOrder.LayoutOrder,

            HorizontalAlignment =
                Enum.HorizontalAlignment.Center,

            Padding =
                UDim.new(0, 6)
        }
    )


    -- ========================================================
    -- CONTENT
    -- ========================================================

    local Content =
        Create(
            "Frame",
            {
                Parent = Main,

                Position =
                    UDim2.new(
                        0,
                        52,
                        0,
                        46
                    ),

                Size =
                    UDim2.new(
                        1,
                        -52,
                        1,
                        -46
                    ),

                BackgroundTransparency = 1,

                BorderSizePixel = 0
            }
        )


    self.ScreenGui =
        ScreenGui

    self.Main =
        Main

    self.Sidebar =
        Sidebar

    self.Content =
        Content


    -- ========================================================
    -- DRAG WINDOW
    -- ========================================================

    do

        local dragging = false

        local dragStart

        local startPosition


        Topbar.InputBegan
            :Connect(
                function(input)

                    if input.UserInputType
                        == Enum.UserInputType.MouseButton1

                        or input.UserInputType
                        == Enum.UserInputType.Touch
                    then

                        dragging = true

                        dragStart =
                            input.Position

                        startPosition =
                            Main.Position
                    end
                end
            )


        Topbar.InputEnded
            :Connect(
                function(input)

                    if input.UserInputType
                        == Enum.UserInputType.MouseButton1

                        or input.UserInputType
                        == Enum.UserInputType.Touch
                    then

                        dragging =
                            false
                    end
                end
            )


        UserInputService
            .InputChanged
            :Connect(
                function(input)

                    if not dragging then
                        return
                    end

                    if input.UserInputType
                        ~= Enum.UserInputType.MouseMovement

                        and input.UserInputType
                        ~= Enum.UserInputType.Touch
                    then
                        return
                    end

                    local delta =
                        input.Position
                        - dragStart

                    Main.Position =
                        UDim2.new(
                            startPosition.X.Scale,
                            startPosition.X.Offset
                                + delta.X,

                            startPosition.Y.Scale,
                            startPosition.Y.Offset
                                + delta.Y
                        )
                end
            )

    end


    -- ========================================================
    -- CLICK OUTSIDE DROPDOWN
    -- ========================================================

    UserInputService
        .InputBegan
        :Connect(
            function(input)

                if not self.ActiveDropdown then
                    return
                end

                if input.UserInputType
                    ~= Enum.UserInputType.MouseButton1

                    and input.UserInputType
                    ~= Enum.UserInputType.Touch
                then
                    return
                end

                local point =
                    input.Position

                local dropdown =
                    self.ActiveDropdown

                if not PointInside(
                    dropdown.Button,
                    point
                )
                    and not PointInside(
                        dropdown.List,
                        point
                    )
                then

                    dropdown:Close()

                    self.ActiveDropdown =
                        nil
                end
            end
        )


    return self
end


-- ============================================================
-- TAB
-- ============================================================

function UI:AddTab(
    id,
    icon
)

    local window =
        self


    local Button =
        Create(
            "TextButton",
            {
                Parent =
                    window.Sidebar,

                Size =
                    UDim2.new(
                        0,
                        44,
                        0,
                        44
                    ),

                BackgroundTransparency = 1,

                BorderSizePixel = 0,

                Text = "",

                AutoButtonColor = false,

                LayoutOrder =
                    #window.Tabs + 1
            }
        )


    local ActiveBar =
        Create(
            "Frame",
            {
                Parent = Button,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0.5,
                        -12
                    ),

                Size =
                    UDim2.new(
                        0,
                        3,
                        0,
                        24
                    ),

                BackgroundColor3 =
                    Theme.Accent,

                BorderSizePixel = 0,

                Visible = false
            }
        )


    local Icon =
        Create(
            "TextLabel",
            {
                Parent = Button,

                BackgroundTransparency = 1,

                Size =
                    UDim2.new(
                        1,
                        0,
                        1,
                        0
                    ),

                Text =
                    tostring(icon or "●"),

                Font =
                    Enum.Font.GothamBold,

                TextColor3 =
                    Theme.Disabled,

                TextSize = 17
            }
        )


    local Page =
        Create(
            "ScrollingFrame",
            {
                Parent =
                    window.Content,

                Size =
                    UDim2.new(
                        1,
                        0,
                        1,
                        0
                    ),

                BackgroundTransparency = 1,

                BorderSizePixel = 0,

                ScrollBarThickness = 3,

                ScrollBarImageColor3 =
                    Theme.Accent,

                CanvasSize =
                    UDim2.new(),

                AutomaticCanvasSize =
                    Enum.AutomaticSize.Y,

                Visible = false
            }
        )


    Create(
        "UIPadding",
        {
            Parent = Page,

            PaddingLeft =
                UDim.new(0, 9),

            PaddingRight =
                UDim.new(0, 9),

            PaddingTop =
                UDim.new(0, 9),

            PaddingBottom =
                UDim.new(0, 9)
        }
    )


    Create(
        "UIListLayout",
        {
            Parent = Page,

            SortOrder =
                Enum.SortOrder.LayoutOrder,

            Padding =
                UDim.new(0, 7)
        }
    )


    local Tab = {

        ID = id,

        Button = Button,

        Icon = Icon,

        ActiveBar = ActiveBar,

        Page = Page,

        Window = window,

        Sections = {}
    }


    function Tab:SetActive(active)

        Page.Visible =
            active

        ActiveBar.Visible =
            active

        Icon.TextColor3 =
            active
            and Theme.Accent
            or Theme.Muted

        Icon.TextSize =
            active
            and 20
            or 17
    end


    Button.MouseButton1Click
        :Connect(
            function()

                window:SelectTab(
                    id
                )
            end
        )


    window.Tabs[id] =
        Tab


    if not window.ActiveTab then

        window:SelectTab(
            id
        )
    end


    return Tab
end


function UI:SelectTab(id)

    for tabID, tab
        in pairs(self.Tabs)
    do

        tab:SetActive(
            tabID == id
        )
    end

    self.ActiveTab =
        id
end


-- ============================================================
-- SECTION
-- ============================================================

local Section = {}

Section.__index =
    Section


function UI:AddSection(
    tab,
    title
)

    local Container =
        Create(
            "Frame",
            {
                Parent =
                    tab.Page,

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        0
                    ),

                AutomaticSize =
                    Enum.AutomaticSize.Y,

                BackgroundTransparency = 1,

                BorderSizePixel = 0,

                LayoutOrder =
                    #tab.Sections + 1
            }
        )


    local Header =
        Create(
            "TextButton",
            {
                Parent = Container,

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        34
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        12,
                        16,
                        15
                    ),

                BorderSizePixel = 0,

                AutoButtonColor = false,

                Text = ""
            }
        )


    AddStroke(
        Header,
        Theme.Stroke,
        0.25,
        1
    )


    local Label =
        Create(
            "TextLabel",
            {
                Parent = Header,

                BackgroundTransparency = 1,

                Position =
                    UDim2.new(
                        0,
                        11,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        1,
                        -45,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text =
                    string.upper(
                        tostring(title)
                    ),

                TextColor3 =
                    Theme.Text,

                TextSize = 13,

                TextXAlignment =
                    Enum.TextXAlignment.Left
            }
        )


    local Arrow =
        Create(
            "TextLabel",
            {
                Parent = Header,

                BackgroundTransparency = 1,

                Position =
                    UDim2.new(
                        1,
                        -35,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        0,
                        30,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text = "−",

                TextColor3 =
                    Theme.Muted,

                TextSize = 17
            }
        )


    local Items =
        Create(
            "Frame",
            {
                Parent = Container,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0,
                        39
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        0
                    ),

                AutomaticSize =
                    Enum.AutomaticSize.Y,

                BackgroundTransparency = 1
            }
        )


    Create(
        "UIListLayout",
        {
            Parent = Items,

            SortOrder =
                Enum.SortOrder.LayoutOrder,

            Padding =
                UDim.new(0, 5)
        }
    )


    local section =
        setmetatable(
            {
                Window =
                    self,

                Tab =
                    tab,

                Container =
                    Container,

                Header =
                    Header,

                Items =
                    Items,

                Collapsed =
                    false,

                Count =
                    0
            },

            Section
        )


    Header.MouseButton1Click
        :Connect(
            function()

                section.Collapsed =
                    not section.Collapsed

                Items.Visible =
                    not section.Collapsed

                Arrow.Text =
                    section.Collapsed
                    and "+"
                    or "−"
            end
        )


    table.insert(
        tab.Sections,
        section
    )


    return section
end


-- ============================================================
-- BASE ROW
-- ============================================================

function Section:CreateRow(
    height
)

    self.Count += 1


    local Row =
        Create(
            "Frame",
            {
                Parent =
                    self.Items,

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        height or 46
                    ),

                BackgroundColor3 =
                    Theme.Card,

                BackgroundTransparency =
                    0.05,

                BorderSizePixel = 0,

                LayoutOrder =
                    self.Count
            }
        )


    AddStroke(
        Row,
        Theme.Stroke,
        0.5,
        1
    )


    return Row
end


-- ============================================================
-- TOGGLE
-- ============================================================

function Section:AddToggle(
    id,
    text,
    defaultValue,
    callback,
    save
)

    local Row =
        self:CreateRow(48)


    local Label =
        Create(
            "TextLabel",
            {
                Parent = Row,

                BackgroundTransparency = 1,

                Position =
                    UDim2.new(
                        0,
                        11,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        1,
                        -78,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.GothamMedium,

                Text =
                    tostring(text),

                TextColor3 =
                    Theme.Text,

                TextSize = 12,

                TextXAlignment =
                    Enum.TextXAlignment.Left
            }
        )


    local Toggle =
        Create(
            "TextButton",
            {
                Parent = Row,

                Position =
                    UDim2.new(
                        1,
                        -60,
                        0.5,
                        -13
                    ),

                Size =
                    UDim2.new(
                        0,
                        48,
                        0,
                        26
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        27,
                        32,
                        31
                    ),

                BorderSizePixel = 0,

                Text = "",

                AutoButtonColor = false
            }
        )


    local Stroke =
        AddStroke(
            Toggle,
            Theme.Stroke,
            0.2,
            1
        )


    local Indicator =
        Create(
            "Frame",
            {
                Parent = Toggle,

                Position =
                    UDim2.new(
                        0,
                        4,
                        0,
                        4
                    ),

                Size =
                    UDim2.new(
                        0,
                        18,
                        0,
                        18
                    ),

                BackgroundColor3 =
                    Theme.Muted,

                BorderSizePixel = 0
            }
        )


    local state =
        defaultValue == true


    local function Render(animated)

        local targetPosition =
            state
            and UDim2.new(
                1,
                -22,
                0,
                4
            )
            or UDim2.new(
                0,
                4,
                0,
                4
            )


        Toggle.BackgroundColor3 =
            state
            and Theme.AccentSoft
            or Color3.fromRGB(
                27,
                32,
                31
            )


        Stroke.Color =
            state
            and Theme.Accent
            or Theme.Stroke


        Indicator.BackgroundColor3 =
            state
            and Theme.Text
            or Theme.Muted


        if animated then

            TweenService:Create(
                Indicator,
                TweenInfo.new(0.14),
                {
                    Position =
                        targetPosition
                }
            ):Play()

        else

            Indicator.Position =
                targetPosition

        end
    end


    local function Set(
        value,
        invokeCallback
    )

        state =
            value == true

        Render(true)

        if invokeCallback ~= false
            and callback
        then

            callback(state)
        end
    end


    Toggle.MouseButton1Click
        :Connect(
            function()

                Set(
                    not state,
                    true
                )
            end
        )


    Render(false)


    local Control = {

        Type = "Toggle",

        Get =
            function()

                return state
            end,

        Set =
            Set
    }


    RegisterControl(
        self.Window,
        id,
        Control,
        save
    )


    return Control
end


-- ============================================================
-- CHECKBOX
-- ============================================================

function Section:AddCheckbox(
    id,
    text,
    defaultValue,
    callback,
    save
)

    local Row =
        self:CreateRow(46)


    Create(
        "TextLabel",
        {
            Parent = Row,

            BackgroundTransparency = 1,

            Position =
                UDim2.new(
                    0,
                    11,
                    0,
                    0
                ),

            Size =
                UDim2.new(
                    1,
                    -58,
                    1,
                    0
                ),

            Font =
                Enum.Font.GothamMedium,

            Text =
                tostring(text),

            TextColor3 =
                Theme.Text,

            TextSize = 12,

            TextXAlignment =
                Enum.TextXAlignment.Left
        }
    )


    local Box =
        Create(
            "TextButton",
            {
                Parent = Row,

                Position =
                    UDim2.new(
                        1,
                        -41,
                        0.5,
                        -13
                    ),

                Size =
                    UDim2.new(
                        0,
                        26,
                        0,
                        26
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        24,
                        29,
                        28
                    ),

                BorderSizePixel = 0,

                Font =
                    Enum.Font.GothamBold,

                Text = "",

                TextSize = 16,

                AutoButtonColor = false
            }
        )


    local Stroke =
        AddStroke(
            Box,
            Theme.Stroke,
            0,
            1
        )


    local state =
        defaultValue == true


    local function Render()

        Box.Text =
            state
            and "✓"
            or ""

        Box.TextColor3 =
            Theme.Text

        Box.BackgroundColor3 =
            state
            and Theme.AccentSoft
            or Color3.fromRGB(
                24,
                29,
                28
            )

        Stroke.Color =
            state
            and Theme.Accent
            or Theme.Stroke
    end


    local function Set(
        value,
        invokeCallback
    )

        state =
            value == true

        Render()

        if invokeCallback ~= false
            and callback
        then

            callback(state)
        end
    end


    Box.MouseButton1Click
        :Connect(
            function()

                Set(
                    not state,
                    true
                )
            end
        )


    Render()


    local Control = {

        Type = "Checkbox",

        Get =
            function()

                return state
            end,

        Set =
            Set
    }


    RegisterControl(
    self.Window,
    id,
    Control,
    save
    )


    return Control
end


-- ============================================================
-- BUTTON
-- ============================================================

function Section:AddButton(
    text,
    callback
)

    local Row =
        self:CreateRow(42)


    local Button =
        Create(
            "TextButton",
            {
                Parent = Row,

                Position =
                    UDim2.new(
                        0,
                        8,
                        0,
                        7
                    ),

                Size =
                    UDim2.new(
                        1,
                        -16,
                        1,
                        -14
                    ),

                BackgroundColor3 =
                    Theme.AccentSoft,

                BorderSizePixel = 0,

                Font =
                    Enum.Font.GothamBold,

                Text =
                    string.upper(
                        tostring(text)
                    ),

                TextColor3 =
                    Theme.Text,

                TextSize = 11,

                AutoButtonColor = false
            }
        )


    AddStroke(
        Button,
        Theme.Accent,
        0.25,
        1
    )


    Button.MouseButton1Click
        :Connect(
            function()

                if callback then
                    callback()
                end
            end
        )


    return Button
end


-- ============================================================
-- TEXTBOX
-- ============================================================

function Section:AddTextbox(
    id,
    text,
    placeholder,
    callback,
    save
)

    local Row =
        self:CreateRow(56)


    Create(
        "TextLabel",
        {
            Parent = Row,

            BackgroundTransparency = 1,

            Position =
                UDim2.new(
                    0,
                    10,
                    0,
                    5
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    18
                ),

            Font =
                Enum.Font.GothamMedium,

            Text =
                tostring(text),

            TextColor3 =
                Theme.Text,

            TextSize = 11,

            TextXAlignment =
                Enum.TextXAlignment.Left
        }
    )


    local Box =
        Create(
            "TextBox",
            {
                Parent = Row,

                Position =
                    UDim2.new(
                        0,
                        9,
                        0,
                        27
                    ),

                Size =
                    UDim2.new(
                        1,
                        -18,
                        0,
                        23
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        10,
                        14,
                        13
                    ),

                BorderSizePixel = 0,

                Font =
                    Enum.Font.Gotham,

                PlaceholderText =
                    tostring(
                        placeholder
                        or ""
                    ),

                PlaceholderColor3 =
                    Theme.Disabled,

                Text = "",

                TextColor3 =
                    Theme.Text,

                TextSize = 11,

                ClearTextOnFocus =
                    false,

                TextXAlignment =
                    Enum.TextXAlignment.Left
            }
        )


    AddStroke(
        Box,
        Theme.Stroke,
        0.3,
        1
    )


    Box.FocusLost
        :Connect(
            function()

                if callback then
                    callback(
                        Box.Text
                    )
                end
            end
        )


    local Control = {

        Type = "Textbox",

        Get =
            function()

                return Box.Text
            end,

        Set =
            function(value)

                Box.Text =
                    tostring(
                        value
                        or ""
                    )
            end
    }


    RegisterControl(
    self.Window,
    id,
    Control,
    save
    )


    return Control
end


-- ============================================================
-- DROPDOWN
-- ============================================================

function Section:AddDropdown(
    id,
    text,
    options,
    multi,
    defaultValue,
    callback,
    save
)

    local window =
        self.Window


    local Row =
        self:CreateRow(55)


    Create(
        "TextLabel",
        {
            Parent = Row,

            BackgroundTransparency = 1,

            Position =
                UDim2.new(
                    0,
                    10,
                    0,
                    4
                ),

            Size =
                UDim2.new(
                    1,
                    -20,
                    0,
                    18
                ),

            Font =
                Enum.Font.GothamMedium,

            Text =
                tostring(text),

            TextColor3 =
                Theme.Text,

            TextSize = 11,

            TextXAlignment =
                Enum.TextXAlignment.Left
        }
    )


    local Button =
        Create(
            "TextButton",
            {
                Parent = Row,

                Position =
                    UDim2.new(
                        0,
                        9,
                        0,
                        26
                    ),

                Size =
                    UDim2.new(
                        1,
                        -18,
                        0,
                        24
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        10,
                        14,
                        13
                    ),

                BorderSizePixel = 0,

                Font =
                    Enum.Font.Gotham,

                Text = "Select",

                TextColor3 =
                    Theme.Muted,

                TextSize = 11,

                TextXAlignment =
                    Enum.TextXAlignment.Left,

                AutoButtonColor = false
            }
        )


    AddStroke(
        Button,
        Theme.Stroke,
        0.3,
        1
    )


    local List =
        Create(
            "ScrollingFrame",
            {
                Parent =
                    window.ScreenGui,

                Size =
                    UDim2.new(
                        0,
                        220,
                        0,
                        120
                    ),

                BackgroundColor3 =
                    Color3.fromRGB(
                        10,
                        14,
                        13
                    ),

                BorderSizePixel = 0,

                Visible = false,

                ZIndex = 100,

                ScrollBarThickness = 2,

                CanvasSize =
                    UDim2.new(),

                AutomaticCanvasSize =
                    Enum.AutomaticSize.Y
            }
        )


    AddStroke(
        List,
        Theme.Stroke,
        0,
        1
    )


    Create(
        "UIListLayout",
        {
            Parent = List,

            SortOrder =
                Enum.SortOrder.LayoutOrder
        }
    )


    local selected =
        multi
        and {}
        or nil


    if multi
        and type(defaultValue)
            == "table"
    then

        for key, value
            in pairs(defaultValue)
        do

            if value then
                selected[key] = true
            end
        end

    elseif not multi then

        selected =
            defaultValue
    end


    local function UpdateText()

        if multi then

            local names = {}

            for name, enabled
                in pairs(selected)
            do

                if enabled then
                    table.insert(
                        names,
                        name
                    )
                end
            end

            table.sort(names)

            if #names == 0 then

                Button.Text =
                    "  Select"

            elseif #names == 1 then

                Button.Text =
                    "  " .. names[1]

            else

                Button.Text =
                    "  "
                    .. tostring(#names)
                    .. " selected"
            end

        else

            Button.Text =
                "  "
                .. tostring(
                    selected
                    or "Select"
                )

        end
    end


    local Dropdown = {}


    function Dropdown:Close()

        List.Visible =
            false
    end


    function Dropdown:Open()

        if window.ActiveDropdown
            and window.ActiveDropdown
                ~= Dropdown
        then

            window.ActiveDropdown
                :Close()
        end


        local pos =
            Button.AbsolutePosition

        local size =
            Button.AbsoluteSize


        List.Position =
            UDim2.fromOffset(
                pos.X,
                pos.Y
                    + size.Y
                    + 3
            )


        List.Size =
            UDim2.fromOffset(
                size.X,
                120
            )


        List.Visible =
            true


        window.ActiveDropdown =
            Dropdown
    end


    Dropdown.Button =
        Button

    Dropdown.List =
        List


    Button.MouseButton1Click
        :Connect(
            function()

                if List.Visible then

                    Dropdown:Close()

                    window.ActiveDropdown =
                        nil

                else

                    Dropdown:Open()

                end
            end
        )


    local function RebuildOptions()

        for _, child
            in ipairs(
                List:GetChildren()
            )
        do

            if child:IsA(
                "TextButton"
            )
            then
                child:Destroy()
            end
        end


        for index, option
            in ipairs(options or {})
        do

            local Option =
                Create(
                    "TextButton",
                    {
                        Parent = List,

                        Size =
                            UDim2.new(
                                1,
                                0,
                                0,
                                28
                            ),

                        BackgroundColor3 =
                            Theme.Card,

                        BackgroundTransparency =
                            0.15,

                        BorderSizePixel = 0,

                        Font =
                            Enum.Font.Gotham,

                        Text =
                            "  "
                            .. tostring(
                                option
                            ),

                        TextColor3 =
                            Theme.Text,

                        TextSize = 11,

                        TextXAlignment =
                            Enum.TextXAlignment.Left,

                        LayoutOrder =
                            index,

                        ZIndex = 101,

                        AutoButtonColor = false
                    }
                )


            Option.MouseButton1Click
                :Connect(
                    function()

                        if multi then

                            selected[option] =
                                not selected[option]

                            UpdateText()

                            if callback then
                                callback(
                                    selected
                                )
                            end

                        else

                            selected =
                                option

                            UpdateText()

                            Dropdown:Close()

                            window.ActiveDropdown =
                                nil

                            if callback then
                                callback(
                                    selected
                                )
                            end

                        end
                    end
                )
        end
    end


    RebuildOptions()

    UpdateText()


    local Control = {

        Type =
            multi
            and "MultiDropdown"
            or "Dropdown",

        Get =
            function()

                if multi then

                    local copy = {}

                    for key, value
                        in pairs(selected)
                    do
                        copy[key] =
                            value
                    end

                    return copy

                else

                    return selected
                end
            end,

        Set =
            function(
                value,
                invokeCallback
            )

                if multi then

                    selected = {}

                    if type(value)
                        == "table"
                    then

                        for key, enabled
                            in pairs(value)
                        do

                            if enabled then
                                selected[key] =
                                    true
                            end
                        end
                    end

                else

                    selected =
                        value
                end


                UpdateText()


                if invokeCallback ~= false
                    and callback
                then

                    callback(
                        selected
                    )
                end
            end,

        SetOptions =
            function(
                newOptions
            )

                options =
                    newOptions
                    or {}

                RebuildOptions()
            end
    }


    RegisterControl(
    window,
    id,
    Control,
    save
    )


    return Control
end


-- ============================================================
-- CONTROL ACCESS
-- ============================================================

function UI:GetControl(id)

    return
        self.Controls[id]
end


function UI:GetControls()

    return
        self.Controls
end


-- ============================================================
-- DESTROY
-- ============================================================

function UI:Destroy()

    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end
end


return UI