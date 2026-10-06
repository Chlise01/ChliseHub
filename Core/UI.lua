-- ============================================================
-- CHLISE HUB
-- Core/UI.lua
-- ============================================================

local UI = {}

-- ============================================================
-- SERVICES
-- ============================================================

local Players =
    game:GetService("Players")

local CoreGui =
    game:GetService("CoreGui")

local UserInputService =
    game:GetService("UserInputService")

local TweenService =
    game:GetService("TweenService")

local RunService =
    game:GetService("RunService")


local LocalPlayer =
    Players.LocalPlayer


-- ============================================================
-- THEME
-- ============================================================

local Theme = {

    Accent =
        Color3.fromRGB(
            255,
            75,
            85
        ),

    AccentSoft =
        Color3.fromRGB(
            255,
            105,
            113
        ),

    Main =
        Color3.fromRGB(
            8,
            11,
            10
        ),

    Top =
        Color3.fromRGB(
            8,
            10,
            10
        ),

    Sidebar =
        Color3.fromRGB(
            4,
            7,
            6
        ),

    Card =
        Color3.fromRGB(
            18,
            23,
            22
        ),

    CardStroke =
        Color3.fromRGB(
            67,
            73,
            72
        ),

    Text =
        Color3.fromRGB(
            245,
            247,
            248
        ),

    SubText =
        Color3.fromRGB(
            157,
            164,
            168
        ),

    ToggleOff =
        Color3.fromRGB(
            57,
            63,
            66
        ),

    ToggleDot =
        Color3.fromRGB(
            205,
            210,
            213
        ),

    Dropdown =
        Color3.fromRGB(
            38,
            43,
            42
        ),

    DropdownOption =
        Color3.fromRGB(
            25,
            30,
            29
        )
}


-- ============================================================
-- TAB ORDER
-- ============================================================

local TAB_ORDER = {

    FARM =
        1,

    PROGRESS =
        2,

    ESP =
        3,

    SETTINGS =
        4

}


-- ============================================================
-- HELPERS
-- ============================================================

local function New(
    class,
    properties
)

    local object =
        Instance.new(
            class
        )


    for key, value
        in pairs(
            properties or {}
        )
    do

        object[key] =
            value

    end


    return object
end


local function Corner(
    parent,
    radius
)

    return New(
        "UICorner",
        {
            Parent =
                parent,

            CornerRadius =
                UDim.new(
                    0,
                    radius or 8
                )
        }
    )

end


local function Stroke(
    parent,
    color,
    transparency,
    thickness
)

    return New(
        "UIStroke",
        {
            Parent =
                parent,

            Color =
                color
                or Theme.CardStroke,

            Transparency =
                transparency
                or 0,

            Thickness =
                thickness
                or 1
        }
    )

end


local function CopyTable(
    value
)

    local result = {}


    if type(value)
        ~= "table"
    then
        return result
    end


    for key, item
        in pairs(value)
    do

        result[key] =
            item

    end


    return result
end


local function ValueEquals(
    first,
    second
)

    if type(first)
        ~= type(second)
    then
        return false
    end


    if type(first)
        ~= "table"
    then
        return first
            == second
    end


    for key, value
        in pairs(first)
    do

        if second[key]
            ~= value
        then
            return false
        end
    end


    for key, value
        in pairs(second)
    do

        if first[key]
            ~= value
        then
            return false
        end
    end


    return true
end


local function SetControlMethod(
    control,
    callback
)

    return function(
        first,
        second,
        third
    )

        -- support:
        --
        -- control.Set(value, invoke)
        -- control:Set(value, invoke)

        if first
            == control
        then

            return callback(
                second,
                third
            )

        end


        return callback(
            first,
            second
        )

    end

end


-- ============================================================
-- WINDOW
-- ============================================================

function UI.new(
    config
)

    config =
        config or {}


    local Window = {

        Controls =
            {},

        Tabs =
            {},

        Sections =
            {},

        CurrentTab =
            nil,

        OpenDropdown =
            nil,

        Destroyed =
            false

    }


    -- ========================================================
    -- REMOVE OLD UI
    -- ========================================================

    pcall(function()

        local old =
            CoreGui:
            FindFirstChild(
                "ChliseHub"
            )


        if old then
            old:
            Destroy()
        end

    end)


    pcall(function()

        local old =
            CoreGui:
            FindFirstChild(
                "ChliseHubToggle"
            )


        if old then
            old:
            Destroy()
        end

    end)


    -- ========================================================
    -- SCREEN GUI
    -- ========================================================

    local ScreenGui =
        New(
            "ScreenGui",
            {
                Name =
                    "ChliseHub",

                ResetOnSpawn =
                    false,

                IgnoreGuiInset =
                    false,

                ZIndexBehavior =
                    Enum.ZIndexBehavior.Sibling
            }
        )


    pcall(function()

        if syn
            and syn.protect_gui
        then

            syn.protect_gui(
                ScreenGui
            )

        end

    end)


    ScreenGui.Parent =
        CoreGui


    Window.ScreenGui =
        ScreenGui


    -- ========================================================
    -- TOGGLE GUI
    -- ========================================================

    local ToggleGui =
        New(
            "ScreenGui",
            {
                Name =
                    "ChliseHubToggle",

                ResetOnSpawn =
                    false,

                ZIndexBehavior =
                    Enum.ZIndexBehavior.Sibling
            }
        )


    ToggleGui.Parent =
        CoreGui


    local OpenButton =
        New(
            "TextButton",
            {
                Parent =
                    ToggleGui,

                BackgroundColor3 =
                    Theme.Accent,

                BorderSizePixel =
                    0,

                Position =
                    UDim2.new(
                        0.5,
                        -23,
                        0,
                        15
                    ),

                Size =
                    UDim2.new(
                        0,
                        46,
                        0,
                        46
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text =
                    "CH",

                TextColor3 =
                    Color3.new(
                        1,
                        1,
                        1
                    ),

                TextSize =
                    14,

                AutoButtonColor =
                    false,

                Active =
                    true
            }
        )


    Corner(
        OpenButton,
        23
    )


    Stroke(
        OpenButton,
        Color3.fromRGB(
            255,
            130,
            135
        ),
        0.35,
        1
    )


    -- ========================================================
    -- MAIN FRAME
    -- ========================================================

    local Width =
        tonumber(
            config.Width
        )
        or 500


    local Height =
        tonumber(
            config.Height
        )
        or 305


    local MainFrame =
        New(
            "Frame",
            {
                Name =
                    "MainFrame",

                Parent =
                    ScreenGui,

                BackgroundColor3 =
                    Theme.Main,

                BackgroundTransparency =
                    0.12,

                BorderSizePixel =
                    0,

                AnchorPoint =
                    Vector2.new(
                        0.5,
                        0.5
                    ),

                Position =
                    UDim2.fromScale(
                        0.5,
                        0.5
                    ),

                Size =
                    UDim2.fromOffset(
                        Width,
                        Height
                    ),

                ClipsDescendants =
                    false,

                Active =
                    true
            }
        )


    Window.MainFrame =
        MainFrame


    Corner(
        MainFrame,
        14
    )


    Stroke(
        MainFrame,
        Color3.fromRGB(
            48,
            52,
            55
        ),
        0.12,
        1.2
    )


    -- ========================================================
    -- MOBILE SCALE
    -- ========================================================

    local Scale =
        New(
            "UIScale",
            {
                Parent =
                    MainFrame,

                Scale =
                    1
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


        local xScale =
            viewport.X
            / (
                Width
                + 30
            )


        local yScale =
            viewport.Y
            / (
                Height
                + 80
            )


        Scale.Scale =
            math.min(
                1,
                xScale,
                yScale
            )

    end


    UpdateScale()


    if workspace.CurrentCamera then

        workspace.CurrentCamera:
        GetPropertyChangedSignal(
            "ViewportSize"
        ):
        Connect(
            UpdateScale
        )

    end


    -- ========================================================
    -- TOP BAR
    -- ========================================================

    local TopBar =
        New(
            "Frame",
            {
                Name =
                    "TopBar",

                Parent =
                    MainFrame,

                BackgroundColor3 =
                    Theme.Top,

                BackgroundTransparency =
                    0.18,

                BorderSizePixel =
                    0,

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        42
                    ),

                ZIndex =
                    20,

                Active =
                    true
            }
        )


    Corner(
        TopBar,
        14
    )


    local TopFill =
        New(
            "Frame",
            {
                Parent =
                    TopBar,

                BackgroundColor3 =
                    Theme.Top,

                BackgroundTransparency =
                    0.18,

                BorderSizePixel =
                    0,

                Position =
                    UDim2.new(
                        0,
                        0,
                        1,
                        -14
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        14
                    )
            }
        )


    local TopAccent =
        New(
            "Frame",
            {
                Parent =
                    TopBar,

                BackgroundColor3 =
                    Theme.Accent,

                BorderSizePixel =
                    0,

                Position =
                    UDim2.new(
                        0,
                        0,
                        1,
                        -2
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        0,
                        2
                    ),

                ZIndex =
                    22
            }
        )


    local Title =
        New(
            "TextLabel",
            {
                Parent =
                    TopBar,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        0,
                        14,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        1,
                        -120,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text =
                    config.Title
                    or "CHLISE HUB",

                TextColor3 =
                    Theme.AccentSoft,

                TextSize =
                    15,

                TextXAlignment =
                    Enum.TextXAlignment.Left,

                ZIndex =
                    23
            }
        )


    local Version =
        New(
            "TextLabel",
            {
                Parent =
                    TopBar,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        1,
                        -125,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        0,
                        52,
                        1,
                        0
                    ),

                Font =
                    Enum.Font.Gotham,

                Text =
                    config.Version
                    or "v2.0",

                TextColor3 =
                    Color3.fromRGB(
                        255,
                        160,
                        160
                    ),

                TextSize =
                    9,

                TextXAlignment =
                    Enum.TextXAlignment.Right,

                ZIndex =
                    23
            }
        )


    local Minimize =
        New(
            "TextButton",
            {
                Parent =
                    TopBar,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        1,
                        -65,
                        0,
                        5
                    ),

                Size =
                    UDim2.fromOffset(
                        30,
                        30
                    ),

                Font =
                    Enum.Font.GothamBold,

                Text =
                    "−",

                TextColor3 =
                    Color3.fromRGB(
                        235,
                        235,
                        238
                    ),

                TextSize =
                    17,

                AutoButtonColor =
                    false,

                ZIndex =
                    24
            }
        )


    local Close =
        New(
            "TextButton",
            {
                Parent =
                    TopBar,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        1,
                        -35,
                        0,
                        5
                    ),

                Size =
                    UDim2.fromOffset(
                        30,
                        30
                    ),

                Font =
                    Enum.Font.GothamMedium,

                Text =
                    "X",

                TextColor3 =
                    Color3.fromRGB(
                        235,
                        235,
                        238
                    ),

                TextSize =
                    14,

                AutoButtonColor =
                    false,

                ZIndex =
                    24
            }
        )


    -- ========================================================
    -- DRAG
    -- ========================================================

    do

        local dragging =
            false

        local dragStart =
            nil

        local startPosition =
            nil

        local dragInput =
            nil


        TopBar.InputBegan:
        Connect(function(input)

            if input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then

                dragging =
                    true

                dragStart =
                    input.Position

                startPosition =
                    MainFrame.Position


                input.Changed:
                Connect(function()

                    if input.UserInputState
                        == Enum.UserInputState.End
                    then

                        dragging =
                            false

                    end

                end)

            end

        end)


        TopBar.InputChanged:
        Connect(function(input)

            if input.UserInputType
                    == Enum.UserInputType.MouseMovement
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then

                dragInput =
                    input

            end

        end)


        UserInputService.InputChanged:
        Connect(function(input)

            if not dragging
                or input
                    ~= dragInput
            then
                return
            end


            local delta =
                input.Position
                - dragStart


            MainFrame.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )

        end)

    end


    -- ========================================================
    -- CONTAINER
    -- ========================================================

    local Container =
        New(
            "Frame",
            {
                Parent =
                    MainFrame,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0,
                        42
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        1,
                        -42
                    )
            }
        )


    -- ========================================================
    -- ICON SIDEBAR
    -- ========================================================

    local Sidebar =
        New(
            "Frame",
            {
                Parent =
                    Container,

                BackgroundColor3 =
                    Theme.Sidebar,

                BackgroundTransparency =
                    0.12,

                BorderSizePixel =
                    0,

                Size =
                    UDim2.new(
                        0,
                        54,
                        1,
                        0
                    )
            }
        )


    local SidebarLine =
        New(
            "Frame",
            {
                Parent =
                    Sidebar,

                BackgroundColor3 =
                    Color3.fromRGB(
                        45,
                        50,
                        49
                    ),

                BackgroundTransparency =
                    0.55,

                BorderSizePixel =
                    0,

                Position =
                    UDim2.new(
                        1,
                        -1,
                        0,
                        0
                    ),

                Size =
                    UDim2.new(
                        0,
                        1,
                        1,
                        0
                    )
            }
        )


    local TabHolder =
        New(
            "Frame",
            {
                Parent =
                    Sidebar,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        0,
                        0,
                        0,
                        8
                    ),

                Size =
                    UDim2.new(
                        1,
                        0,
                        1,
                        -16
                    )
            }
        )


    local TabLayout =
        New(
            "UIListLayout",
            {
                Parent =
                    TabHolder,

                SortOrder =
                    Enum.SortOrder.LayoutOrder,

                Padding =
                    UDim.new(
                        0,
                        5
                    ),

                HorizontalAlignment =
                    Enum.HorizontalAlignment.Center
            }
        )


    -- ========================================================
    -- CONTENT
    -- ========================================================

    local ContentHolder =
        New(
            "Frame",
            {
                Parent =
                    Container,

                BackgroundTransparency =
                    1,

                Position =
                    UDim2.new(
                        0,
                        63,
                        0,
                        8
                    ),

                Size =
                    UDim2.new(
                        1,
                        -71,
                        1,
                        -16
                    )
            }
        )


    -- ========================================================
    -- DROPDOWN OVERLAY LAYER
    -- ========================================================

    local Overlay =
        New(
            "Frame",
            {
                Parent =
                    ScreenGui,

                BackgroundTransparency =
                    1,

                Size =
                    UDim2.fromScale(
                        1,
                        1
                    ),

                Visible =
                    true,

                ZIndex =
                    5000
            }
        )


    Overlay.Active =
        false


    -- ========================================================
    -- CLOSE DROPDOWN
    -- ========================================================

    function Window:CloseDropdown()

        if self.OpenDropdown then

            local dropdown =
                self.OpenDropdown


            self.OpenDropdown =
                nil


            dropdown.Close()

        end

    end


    -- ========================================================
    -- TAB SELECT
    -- ========================================================

    function Window:SelectTab(
        id
    )

        id =
            tostring(id)


        local selected =
            self.Tabs[id]


        if not selected then
            return
        end


        self:CloseDropdown()


        self.CurrentTab =
            id


        for tabId, tab
            in pairs(
                self.Tabs
            )
        do

            local active =
                tabId
                == id


            tab.Page.Visible =
                active


            tab.Accent.Visible =
                active


            tab.Icon.TextColor3 =
                active
                and Theme.AccentSoft
                or Color3.fromRGB(
                    165,
                    171,
                    175
                )


            tab.Icon.TextSize =
                active
                and 20
                or 17


            tab.Button.BackgroundTransparency =
                1

        end

    end


    -- ========================================================
    -- ADD TAB
    -- ========================================================

    function Window:AddTab(
        id,
        icon
    )

        id =
            tostring(id)


        if self.Tabs[id] then

            return
                self.Tabs[id]

        end


        local button =
            New(
                "TextButton",
                {
                    Parent =
                        TabHolder,

                    BackgroundTransparency =
                        1,

                    BorderSizePixel =
                        0,

                    Size =
                        UDim2.fromOffset(
                            48,
                            42
                        ),

                    Text =
                        "",

                    AutoButtonColor =
                        false,

                    LayoutOrder =
                        TAB_ORDER[id]
                        or 100
                }
            )


        local accent =
            New(
                "Frame",
                {
                    Parent =
                        button,

                    BackgroundColor3 =
                        Theme.Accent,

                    BorderSizePixel =
                        0,

                    Position =
                        UDim2.new(
                            0,
                            0,
                            0.5,
                            -12
                        ),

                    Size =
                        UDim2.fromOffset(
                            3,
                            24
                        ),

                    Visible =
                        false
                }
            )


        Corner(
            accent,
            2
        )


        local iconLabel =
            New(
                "TextLabel",
                {
                    Parent =
                        button,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            4,
                            0,
                            0
                        ),

                    Size =
                        UDim2.new(
                            1,
                            -4,
                            1,
                            0
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        icon
                        or "•",

                    TextColor3 =
                        Color3.fromRGB(
                            165,
                            171,
                            175
                        ),

                    TextSize =
                        17
                }
            )


        local page =
            New(
                "ScrollingFrame",
                {
                    Parent =
                        ContentHolder,

                    BackgroundTransparency =
                        1,

                    BorderSizePixel =
                        0,

                    Size =
                        UDim2.fromScale(
                            1,
                            1
                        ),

                    CanvasSize =
                        UDim2.new(
                            0,
                            0,
                            0,
                            0
                        ),

                    AutomaticCanvasSize =
                        Enum.AutomaticSize.Y,

                    ScrollBarThickness =
                        2,

                    ScrollBarImageColor3 =
                        Theme.Accent,

                    ScrollBarImageTransparency =
                        0.25,

                    Visible =
                        false
                }
            )


        local padding =
            New(
                "UIPadding",
                {
                    Parent =
                        page,

                    PaddingRight =
                        UDim.new(
                            0,
                            4
                        ),

                    PaddingBottom =
                        UDim.new(
                            0,
                            10
                        )
                }
            )


        local layout =
            New(
                "UIListLayout",
                {
                    Parent =
                        page,

                    SortOrder =
                        Enum.SortOrder.LayoutOrder,

                    Padding =
                        UDim.new(
                            0,
                            7
                        )
                }
            )


        local tab = {

            Id =
                id,

            Button =
                button,

            Icon =
                iconLabel,

            Accent =
                accent,

            Page =
                page,

            Layout =
                layout,

            SectionCounter =
                0

        }


        self.Tabs[id] =
            tab


        button.MouseButton1Click:
        Connect(function()

            self:
            SelectTab(
                id
            )

        end)


        -- Fixed default:
        -- FARM selalu dipilih ketika tersedia.

        if id
            == "FARM"
        then

            self:
            SelectTab(
                "FARM"
            )

        elseif not self.CurrentTab then

            self:
            SelectTab(
                id
            )

        end


        return tab
    end


    -- ========================================================
    -- CONTROL REGISTRATION
    -- ========================================================

    local function RegisterControl(
        id,
        control,
        save
    )

        if not id then
            return control
        end


        control.Id =
            id


        control.Save =
            save
            ~= false


        Window.Controls[id] =
            control


        return control
    end


    function Window:GetControl(
        id
    )

        return
            self.Controls[id]

    end


    function Window:GetControls()

        return
            self.Controls

    end


    -- ========================================================
    -- ADD SECTION
    -- ========================================================

    function Window:AddSection(
        tab,
        title
    )

        if type(tab)
            == "string"
        then

            tab =
                self.Tabs[tab]

        end


        if not tab then
            return nil
        end


        tab.SectionCounter +=
            1


        local sectionOrder =
            tab.SectionCounter


        local Section = {

            Window =
                self,

            Tab =
                tab,

            ItemCounter =
                0,

            Items =
                {},

            Open =
                true

        }


        -- ====================================================
        -- SECTION WRAPPER
        -- ====================================================

        local Wrapper =
            New(
                "Frame",
                {
                    Parent =
                        tab.Page,

                    BackgroundTransparency =
                        1,

                    Size =
                        UDim2.new(
                            1,
                            0,
                            0,
                            32
                        ),

                    AutomaticSize =
                        Enum.AutomaticSize.Y,

                    LayoutOrder =
                        sectionOrder
                }
            )


        local WrapperLayout =
            New(
                "UIListLayout",
                {
                    Parent =
                        Wrapper,

                    SortOrder =
                        Enum.SortOrder.LayoutOrder,

                    Padding =
                        UDim.new(
                            0,
                            6
                        )
                }
            )


        -- ====================================================
        -- SECTION HEADER
        -- ====================================================

        local Header =
            New(
                "TextButton",
                {
                    Parent =
                        Wrapper,

                    BackgroundTransparency =
                        1,

                    Size =
                        UDim2.new(
                            1,
                            0,
                            0,
                            30
                        ),

                    LayoutOrder =
                        0,

                    AutoButtonColor =
                        false,

                    Text =
                        ""
                }
            )


        local HeaderTitle =
            New(
                "TextLabel",
                {
                    Parent =
                        Header,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            2,
                            0,
                            0
                        ),

                    Size =
                        UDim2.new(
                            1,
                            -30,
                            1,
                            -2
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        string.upper(
                            tostring(
                                title or ""
                            )
                        ),

                    TextColor3 =
                        Theme.Text,

                    TextSize =
                        12,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


        local Arrow =
            New(
                "TextLabel",
                {
                    Parent =
                        Header,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            1,
                            -22,
                            0,
                            0
                        ),

                    Size =
                        UDim2.fromOffset(
                            20,
                            28
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        "▼",

                    TextColor3 =
                        Theme.SubText,

                    TextSize =
                        10
                }
            )


        local HeaderLine =
            New(
                "Frame",
                {
                    Parent =
                        Header,

                    BackgroundColor3 =
                        Theme.Accent,

                    BackgroundTransparency =
                        0.08,

                    BorderSizePixel =
                        0,

                    Position =
                        UDim2.new(
                            0,
                            0,
                            1,
                            -2
                        ),

                    Size =
                        UDim2.new(
                            1,
                            0,
                            0,
                            2
                        )
                }
            )


        local ItemsHolder =
            New(
                "Frame",
                {
                    Parent =
                        Wrapper,

                    BackgroundTransparency =
                        1,

                    Size =
                        UDim2.new(
                            1,
                            0,
                            0,
                            0
                        ),

                    AutomaticSize =
                        Enum.AutomaticSize.Y,

                    LayoutOrder =
                        1
                }
            )


        local ItemsLayout =
            New(
                "UIListLayout",
                {
                    Parent =
                        ItemsHolder,

                    SortOrder =
                        Enum.SortOrder.LayoutOrder,

                    Padding =
                        UDim.new(
                            0,
                            6
                        )
                }
            )


        Section.Wrapper =
            Wrapper

        Section.ItemsHolder =
            ItemsHolder


        Header.MouseButton1Click:
        Connect(function()

            Section.Open =
                not Section.Open


            ItemsHolder.Visible =
                Section.Open


            Arrow.Text =
                Section.Open
                and "▼"
                or "▲"


            self:
            CloseDropdown()

        end)


        -- ====================================================
        -- CARD CREATOR
        -- ====================================================

        local function CreateCard(
            height
        )

            Section.ItemCounter +=
                1


            local card =
                New(
                    "Frame",
                    {
                        Parent =
                            ItemsHolder,

                        BackgroundColor3 =
                            Theme.Card,

                        BackgroundTransparency =
                            0.20,

                        BorderSizePixel =
                            0,

                        Size =
                            UDim2.new(
                                1,
                                0,
                                0,
                                height or 48
                            ),

                        LayoutOrder =
                            Section.ItemCounter
                    }
                )


            Corner(
                card,
                9
            )


            Stroke(
                card,
                Theme.CardStroke,
                0.56,
                1
            )


            table.insert(
                Section.Items,
                card
            )


            return card
        end


        local function CreateText(
            card,
            label
        )

            New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
                            0,
                            7
                        ),

                    Size =
                        UDim2.new(
                            0.68,
                            0,
                            0,
                            18
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        label,

                    TextColor3 =
                        Theme.Text,

                    TextSize =
                        12,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


            return New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
                            0,
                            25
                        ),

                    Size =
                        UDim2.new(
                            0.68,
                            0,
                            0,
                            15
                        ),

                    Font =
                        Enum.Font.Gotham,

                    Text =
                        "Status: Nonaktif / Aktif",

                    TextColor3 =
                        Theme.SubText,

                    TextSize =
                        9,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )

        end


        -- ====================================================
        -- TOGGLE
        -- ====================================================

        function Section:AddToggle(
            id,
            label,
            default,
            callback,
            save
        )

            local card =
                CreateCard(
                    48
                )


            local sub =
                CreateText(
                    card,
                    label
                )


            local box =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.ToggleOff,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                1,
                                -51,
                                0,
                                12
                            ),

                        Size =
                            UDim2.fromOffset(
                                40,
                                24
                            ),

                        Text =
                            "",

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                box,
                12
            )


            local indicator =
                New(
                    "Frame",
                    {
                        Parent =
                            box,

                        BackgroundColor3 =
                            Theme.ToggleDot,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.fromOffset(
                                3,
                                3
                            ),

                        Size =
                            UDim2.fromOffset(
                                18,
                                18
                            )
                    }
                )


            Corner(
                indicator,
                9
            )


            local state =
                default == true


            local control = {}


            local function Render(
                instant
            )

                sub.Text =
                    state
                    and "Status: Aktif"
                    or "Status: Nonaktif"


                local boxColor =
                    state
                    and Theme.Accent
                    or Theme.ToggleOff


                local position =
                    state
                    and UDim2.new(
                        1,
                        -21,
                        0,
                        3
                    )
                    or UDim2.fromOffset(
                        3,
                        3
                    )


                local dotColor =
                    state
                    and Color3.new(
                        1,
                        1,
                        1
                    )
                    or Theme.ToggleDot


                if instant then

                    box.BackgroundColor3 =
                        boxColor

                    indicator.Position =
                        position

                    indicator.BackgroundColor3 =
                        dotColor

                else

                    TweenService:
                    Create(
                        box,
                        TweenInfo.new(
                            0.16
                        ),
                        {
                            BackgroundColor3 =
                                boxColor
                        }
                    ):
                    Play()


                    TweenService:
                    Create(
                        indicator,
                        TweenInfo.new(
                            0.16
                        ),
                        {
                            Position =
                                position,

                            BackgroundColor3 =
                                dotColor
                        }
                    ):
                    Play()

                end

            end


            control.Get =
                function()
                    return state
                end


            control.Set =
                SetControlMethod(
                    control,

                    function(
                        value,
                        invoke
                    )

                        local newState =
                            value == true


                        local changed =
                            state
                            ~= newState


                        state =
                            newState


                        Render(
                            not changed
                        )


                        if invoke
                                ~= false
                            and type(callback)
                                == "function"
                        then

                            callback(
                                state
                            )

                        end


                        return state

                    end
                )


            box.MouseButton1Click:
            Connect(function()

                control.Set(
                    not state,
                    true
                )

            end)


            Render(
                true
            )


            return RegisterControl(
                id,
                control,
                save
            )
        end


        -- ====================================================
        -- CHECKBOX
        -- ====================================================

        function Section:AddCheckbox(
            id,
            label,
            default,
            callback,
            save
        )

            local card =
                CreateCard(
                    44
                )


            New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
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
                        Enum.Font.GothamBold,

                    Text =
                        label,

                    TextColor3 =
                        Theme.Text,

                    TextSize =
                        12,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


            local box =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Color3.fromRGB(
                                24,
                                28,
                                28
                            ),

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                1,
                                -39,
                                0.5,
                                -10
                            ),

                        Size =
                            UDim2.fromOffset(
                                20,
                                20
                            ),

                        Text =
                            "",

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                box,
                4
            )


            local boxStroke =
                Stroke(
                    box,
                    Color3.fromRGB(
                        100,
                        106,
                        108
                    ),
                    0.25,
                    1.2
                )


            local check =
                New(
                    "TextLabel",
                    {
                        Parent =
                            box,

                        BackgroundTransparency =
                            1,

                        Size =
                            UDim2.fromScale(
                                1,
                                1
                            ),

                        Font =
                            Enum.Font.GothamBold,

                        Text =
                            "✓",

                        TextColor3 =
                            Color3.new(
                                1,
                                1,
                                1
                            ),

                        TextSize =
                            14,

                        Visible =
                            false
                    }
                )


            local state =
                default == true


            local control = {}


            local function Render()

                check.Visible =
                    state


                box.BackgroundColor3 =
                    state
                    and Theme.Accent
                    or Color3.fromRGB(
                        24,
                        28,
                        28
                    )


                boxStroke.Color =
                    state
                    and Theme.AccentSoft
                    or Color3.fromRGB(
                        100,
                        106,
                        108
                    )

            end


            control.Get =
                function()
                    return state
                end


            control.Set =
                SetControlMethod(
                    control,

                    function(
                        value,
                        invoke
                    )

                        state =
                            value == true


                        Render()


                        if invoke
                                ~= false
                            and type(callback)
                                == "function"
                        then

                            callback(
                                state
                            )

                        end


                        return state

                    end
                )


            box.MouseButton1Click:
            Connect(function()

                control.Set(
                    not state,
                    true
                )

            end)


            Render()


            return RegisterControl(
                id,
                control,
                save
            )
        end


        -- ====================================================
        -- BUTTON
        -- ====================================================

        function Section:AddButton(
            label,
            callback
        )

            local card =
                CreateCard(
                    42
                )


            local button =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.Dropdown,

                        BackgroundTransparency =
                            0.08,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                0,
                                9,
                                0,
                                7
                            ),

                        Size =
                            UDim2.new(
                                1,
                                -18,
                                1,
                                -14
                            ),

                        Font =
                            Enum.Font.GothamBold,

                        Text =
                            label,

                        TextColor3 =
                            Theme.Text,

                        TextSize =
                            11,

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                button,
                7
            )


            button.MouseEnter:
            Connect(function()

                TweenService:
                Create(
                    button,
                    TweenInfo.new(
                        0.12
                    ),
                    {
                        BackgroundColor3 =
                            Color3.fromRGB(
                                52,
                                40,
                                41
                            )
                    }
                ):
                Play()

            end)


            button.MouseLeave:
            Connect(function()

                TweenService:
                Create(
                    button,
                    TweenInfo.new(
                        0.12
                    ),
                    {
                        BackgroundColor3 =
                            Theme.Dropdown
                    }
                ):
                Play()

            end)


            button.MouseButton1Click:
            Connect(function()

                if type(callback)
                    == "function"
                then

                    task.spawn(
                        callback
                    )

                end

            end)


            return button
        end



        -- ====================================================
        -- BUTTON ROW
        -- ====================================================

        function Section:AddButtonRow(
            leftLabel,
            leftCallback,
            rightLabel,
            rightCallback
        )

            local card =
                CreateCard(
                    42
                )


            local leftButton =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.Dropdown,

                        BackgroundTransparency =
                            0.08,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                0,
                                9,
                                0,
                                7
                            ),

                        Size =
                            UDim2.new(
                                0.5,
                                -12,
                                1,
                                -14
                            ),

                        Font =
                            Enum.Font.GothamBold,

                        Text =
                            leftLabel,

                        TextColor3 =
                            Theme.Text,

                        TextSize =
                            11,

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                leftButton,
                7
            )


            local rightButton =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.Dropdown,

                        BackgroundTransparency =
                            0.08,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                0.5,
                                3,
                                0,
                                7
                            ),

                        Size =
                            UDim2.new(
                                0.5,
                                -12,
                                1,
                                -14
                            ),

                        Font =
                            Enum.Font.GothamBold,

                        Text =
                            rightLabel,

                        TextColor3 =
                            Theme.Text,

                        TextSize =
                            11,

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                rightButton,
                7
            )


            local function BindButton(
                button,
                callback
            )

                button.MouseEnter:
                Connect(function()

                    TweenService:
                    Create(
                        button,
                        TweenInfo.new(
                            0.12
                        ),
                        {
                            BackgroundColor3 =
                                Color3.fromRGB(
                                    52,
                                    40,
                                    41
                                )
                        }
                    ):
                    Play()

                end)


                button.MouseLeave:
                Connect(function()

                    TweenService:
                    Create(
                        button,
                        TweenInfo.new(
                            0.12
                        ),
                        {
                            BackgroundColor3 =
                                Theme.Dropdown
                        }
                    ):
                    Play()

                end)


                button.MouseButton1Click:
                Connect(function()

                    if type(callback)
                        == "function"
                    then

                        task.spawn(
                            callback
                        )

                    end

                end)

            end


            BindButton(
                leftButton,
                leftCallback
            )


            BindButton(
                rightButton,
                rightCallback
            )


            return {
                Instance =
                    card,

                Left =
                    leftButton,

                Right =
                    rightButton
            }
        end


        -- ====================================================
        -- TEXTBOX
        -- ====================================================

        function Section:AddTextbox(
            id,
            label,
            placeholder,
            callback,
            save
        )

            local card =
                CreateCard(
                    48
                )


            New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
                            0,
                            0
                        ),

                    Size =
                        UDim2.new(
                            0.44,
                            0,
                            1,
                            0
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        label,

                    TextColor3 =
                        Theme.Text,

                    TextSize =
                        12,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


            local textbox =
                New(
                    "TextBox",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.Dropdown,

                        BackgroundTransparency =
                            0.10,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                0.48,
                                0,
                                0,
                                8
                            ),

                        Size =
                            UDim2.new(
                                0.49,
                                0,
                                0,
                                32
                            ),

                        Font =
                            Enum.Font.Gotham,

                        PlaceholderText =
                            placeholder
                            or "",

                        PlaceholderColor3 =
                            Theme.SubText,

                        Text =
                            "",

                        TextColor3 =
                            Theme.Text,

                        TextSize =
                            11,

                        ClearTextOnFocus =
                            false
                    }
                )


            Corner(
                textbox,
                7
            )


            Stroke(
                textbox,
                Theme.CardStroke,
                0.65,
                1
            )


            local state =
                ""


            local control = {}

            -- Expose the underlying TextBox for controls that need
            -- focus-aware display formatting (e.g. 1000000 <-> 1M).
            control.Textbox =
                textbox

            control.Input =
                textbox


            control.Get =
                function()
                    return state
                end


            control.Set =
                SetControlMethod(
                    control,

                    function(
                        value,
                        invoke
                    )

                        state =
                            tostring(
                                value or ""
                            )


                        textbox.Text =
                            state


                        if invoke
                                ~= false
                            and type(callback)
                                == "function"
                        then

                            callback(
                                state
                            )

                        end


                        return state

                    end
                )


            textbox.FocusLost:
            Connect(function()

                state =
                    textbox.Text


                if type(callback)
                    == "function"
                then

                    callback(
                        state
                    )

                end

            end)


            return RegisterControl(
                id,
                control,
                save
            )
        end


        -- ====================================================
        -- DROPDOWN
        -- ====================================================

        function Section:AddDropdown(
            id,
            label,
            options,
            multi,
            default,
            callback,
            save
        )

            options =
                CopyTable(
                    options
                )


            local card =
                CreateCard(
                    48
                )


            New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
                            0,
                            7
                        ),

                    Size =
                        UDim2.new(
                            0.49,
                            0,
                            0,
                            18
                        ),

                    Font =
                        Enum.Font.GothamBold,

                    Text =
                        label,

                    TextColor3 =
                        Theme.Text,

                    TextSize =
                        12,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


            New(
                "TextLabel",
                {
                    Parent =
                        card,

                    BackgroundTransparency =
                        1,

                    Position =
                        UDim2.new(
                            0,
                            12,
                            0,
                            25
                        ),

                    Size =
                        UDim2.new(
                            0.49,
                            0,
                            0,
                            15
                        ),

                    Font =
                        Enum.Font.Gotham,

                    Text =
                        multi
                        and "Select Option"
                        or "Select Option",

                    TextColor3 =
                        Theme.SubText,

                    TextSize =
                        9,

                    TextXAlignment =
                        Enum.TextXAlignment.Left
                }
            )


            local mainButton =
                New(
                    "TextButton",
                    {
                        Parent =
                            card,

                        BackgroundColor3 =
                            Theme.Dropdown,

                        BackgroundTransparency =
                            0.10,

                        BorderSizePixel =
                            0,

                        Position =
                            UDim2.new(
                                0.53,
                                0,
                                0,
                                8
                            ),

                        Size =
                            UDim2.new(
                                0.44,
                                0,
                                0,
                                32
                            ),

                        Font =
                            Enum.Font.Gotham,

                        Text =
                            "Select...  ▼",

                        TextColor3 =
                            Theme.Text,

                        TextSize =
                            10,

                        AutoButtonColor =
                            false
                    }
                )


            Corner(
                mainButton,
                7
            )


            local Popup =
                New(
                    "ScrollingFrame",
                    {
                        Parent =
                            ScreenGui,

                        BackgroundColor3 =
                            Color3.fromRGB(
                                12,
                                16,
                                15
                            ),

                        BackgroundTransparency =
                            0.03,

                        BorderSizePixel =
                            0,

                        Size =
                            UDim2.fromOffset(
                                0,
                                0
                            ),

                        CanvasSize =
                            UDim2.new(
                                0,
                                0,
                                0,
                                0
                            ),

                        AutomaticCanvasSize =
                            Enum.AutomaticSize.Y,

                        ScrollBarThickness =
                            2,

                        ScrollBarImageColor3 =
                            Theme.Accent,

                        ScrollBarImageTransparency =
                            0.2,

                        Visible =
                            false,

                        ZIndex =
                            10000
                    }
                )


            Corner(
                Popup,
                7
            )


            Stroke(
                Popup,
                Theme.Accent,
                0.55,
                1
            )


            local PopupLayout =
                New(
                    "UIListLayout",
                    {
                        Parent =
                            Popup,

                        SortOrder =
                            Enum.SortOrder.LayoutOrder
                    }
                )


            local state


            if multi then

                state =
                    type(default)
                        == "table"
                    and CopyTable(
                        default
                    )
                    or {}

            else

                state =
                    default

            end


            local control = {

                OptionButtons =
                    {},

                Open =
                    false

            }


            local function UpdateText()

                if multi then

                    local selected = {}


                    for _, option
                        in ipairs(options)
                    do

                        if state[option]
                            == true
                        then

                            table.insert(
                                selected,
                                option
                            )

                        end
                    end


                    if #selected == 0 then

                        mainButton.Text =
                            "Select...  ▼"

                    elseif #selected == 1 then

                        mainButton.Text =
                            tostring(
                                selected[1]
                            )
                            .. "  ▼"

                    else

                        mainButton.Text =
                            tostring(
                                selected[1]
                            )
                            .. " (+"
                            .. tostring(
                                #selected - 1
                            )
                            .. ")  ▼"

                    end

                else

                    mainButton.Text =
                        state ~= nil
                        and (
                            tostring(
                                state
                            )
                            .. "  ▼"
                        )
                        or "Select...  ▼"

                end

            end


            local function StyleOptions()

                for option, button
                    in pairs(
                        control.OptionButtons
                    )
                do

                    local selected


                    if multi then

                        selected =
                            state[option]
                            == true

                    else

                        selected =
                            state
                            == option

                    end


                    button.BackgroundColor3 =
                        selected
                        and Theme.Accent
                        or Theme.DropdownOption


                    button.BackgroundTransparency =
                        selected
                        and 0.25
                        or 0.40


                    button.TextColor3 =
                        selected
                        and Color3.new(
                            1,
                            1,
                            1
                        )
                        or Color3.fromRGB(
                            195,
                            200,
                            202
                        )

                end

            end


            local function Render()

                UpdateText()
                StyleOptions()

            end


            local function ClosePopup()

                if not control.Open then

                    Popup.Visible =
                        false

                    return
                end


                control.Open =
                    false


                TweenService:
                Create(
                    Popup,
                    TweenInfo.new(
                        0.14
                    ),
                    {
                        Size =
                            UDim2.fromOffset(
                                mainButton.AbsoluteSize.X,
                                0
                            )
                    }
                ):
                Play()


                task.delay(
                    0.14,

                    function()

                        if not control.Open then

                            Popup.Visible =
                                false

                        end

                    end
                )

            end


            local function OpenPopup()

                if Window.OpenDropdown
                    and Window.OpenDropdown
                        ~= control
                then

                    Window:
                    CloseDropdown()

                end


                local absolutePosition =
                    mainButton.AbsolutePosition


                local absoluteSize =
                    mainButton.AbsoluteSize


                local height =
                    math.min(
                        math.max(
                            #options * 28,
                            28
                        ),
                        140
                    )


                Popup.Position =
                    UDim2.fromOffset(
                        absolutePosition.X,
                        absolutePosition.Y
                            + absoluteSize.Y
                            + 4
                    )


                Popup.Size =
                    UDim2.fromOffset(
                        absoluteSize.X,
                        0
                    )


                Popup.Visible =
                    true


                control.Open =
                    true


                Window.OpenDropdown =
                    control


                TweenService:
                Create(
                    Popup,
                    TweenInfo.new(
                        0.14
                    ),
                    {
                        Size =
                            UDim2.fromOffset(
                                absoluteSize.X,
                                height
                            )
                    }
                ):
                Play()

            end


            control.Close =
                ClosePopup


            local function RebuildOptions()

                for _, child
                    in ipairs(
                        Popup:GetChildren()
                    )
                do

                    if child:IsA(
                        "TextButton"
                    )
                    then

                        child:
                        Destroy()

                    end

                end


                table.clear(
                    control.OptionButtons
                )


                for index, option
                    in ipairs(options)
                do

                    local button =
                        New(
                            "TextButton",
                            {
                                Parent =
                                    Popup,

                                BackgroundColor3 =
                                    Theme.DropdownOption,

                                BackgroundTransparency =
                                    0.4,

                                BorderSizePixel =
                                    0,

                                Size =
                                    UDim2.new(
                                        1,
                                        0,
                                        0,
                                        28
                                    ),

                                LayoutOrder =
                                    index,

                                Font =
                                    Enum.Font.Gotham,

                                Text =
                                    "   "
                                    .. tostring(
                                        option
                                    ),

                                TextColor3 =
                                    Color3.fromRGB(
                                        195,
                                        200,
                                        202
                                    ),

                                TextSize =
                                    10,

                                TextXAlignment =
                                    Enum.TextXAlignment.Left,

                                AutoButtonColor =
                                    false,

                                ZIndex =
                                    10001
                            }
                        )


                    control.OptionButtons[
                        option
                    ] =
                        button


                    button.MouseButton1Click:
                    Connect(function()

                        if multi then

                            if state[option]
                                == true
                            then

                                state[option] =
                                    nil

                            else

                                state[option] =
                                    true

                            end


                            Render()


                            if type(callback)
                                == "function"
                            then

                                callback(
                                    CopyTable(
                                        state
                                    )
                                )

                            end

                        else

                            state =
                                option


                            Render()


                            ClosePopup()


                            if Window.OpenDropdown
                                == control
                            then

                                Window.OpenDropdown =
                                    nil

                            end


                            if type(callback)
                                == "function"
                            then

                                callback(
                                    state
                                )

                            end

                        end

                    end)

                end


                Render()

            end


            control.Get =
                function()

                    if multi then

                        return
                            CopyTable(
                                state
                            )

                    end


                    return state

                end


            control.Set =
                SetControlMethod(
                    control,

                    function(
                        value,
                        invoke
                    )

                        if multi then

                            state =
                                type(value)
                                    == "table"
                                and CopyTable(
                                    value
                                )
                                or {}

                        else

                            state =
                                value

                        end


                        Render()


                        if invoke
                                ~= false
                            and type(callback)
                                == "function"
                        then

                            if multi then

                                callback(
                                    CopyTable(
                                        state
                                    )
                                )

                            else

                                callback(
                                    state
                                )

                            end

                        end


                        return
                            control.Get()

                    end
                )


            control.SetOptions =
                SetControlMethod(
                    control,

                    function(
                        newOptions,
                        preserve
                    )

                        options =
                            type(newOptions)
                                == "table"
                            and CopyTable(
                                newOptions
                            )
                            or {}


                        if preserve
                            == false
                        then

                            if multi then

                                state =
                                    {}

                            else

                                state =
                                    nil

                            end

                        else

                            if multi then

                                local allowed = {}


                                for _, option
                                    in ipairs(options)
                                do

                                    allowed[option] =
                                        true

                                end


                                for key
                                    in pairs(
                                        state
                                    )
                                do

                                    if not allowed[
                                        key
                                    ]
                                    then

                                        state[key] =
                                            nil

                                    end

                                end

                            else

                                local found =
                                    false


                                for _, option
                                    in ipairs(options)
                                do

                                    if option
                                        == state
                                    then

                                        found =
                                            true

                                        break
                                    end

                                end


                                if not found then

                                    state =
                                        nil

                                end

                            end

                        end


                        RebuildOptions()


                        return
                            control.Get()

                    end
                )


            mainButton.MouseButton1Click:
            Connect(function()

                if control.Open then

                    ClosePopup()


                    if Window.OpenDropdown
                        == control
                    then

                        Window.OpenDropdown =
                            nil

                    end

                else

                    OpenPopup()

                end

            end)


            RebuildOptions()


            return RegisterControl(
                id,
                control,
                save
            )
        end


        return Section
    end


    -- ========================================================
    -- OUTSIDE CLICK CLOSE DROPDOWN
    -- ========================================================

    UserInputService.InputBegan:
    Connect(function(
        input,
        processed
    )

        if processed then
            return
        end


        if input.UserInputType
                ~= Enum.UserInputType.MouseButton1
            and input.UserInputType
                ~= Enum.UserInputType.Touch
        then
            return
        end


        local dropdown =
            Window.OpenDropdown


        if not dropdown
            or not dropdown.Open
        then
            return
        end


        task.defer(function()

            if Window.OpenDropdown
                == dropdown
                and dropdown.Open
            then

                Window:
                CloseDropdown()

            end

        end)

    end)


    -- ========================================================
    -- VISIBILITY
    -- ========================================================

    local visible =
        true


    local function SetVisible(
        value
    )

        visible =
            value


        MainFrame.Visible =
            visible


        Window:
        CloseDropdown()

    end


    Minimize.MouseButton1Click:
    Connect(function()

        SetVisible(
            false
        )

    end)


    OpenButton.MouseButton1Click:
    Connect(function()

        SetVisible(
            not visible
        )

    end)


    -- ========================================================
    -- DRAG OPEN BUTTON
    -- ========================================================

    do

        local dragging =
            false

        local startInput =
            nil

        local startPosition =
            nil


        OpenButton.InputBegan:
        Connect(function(input)

            if input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then

                dragging =
                    true

                startInput =
                    input.Position

                startPosition =
                    OpenButton.Position

            end

        end)


        UserInputService.InputChanged:
        Connect(function(input)

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
                - startInput


            OpenButton.Position =
                UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset
                        + delta.X,

                    startPosition.Y.Scale,
                    startPosition.Y.Offset
                        + delta.Y
                )

        end)


        UserInputService.InputEnded:
        Connect(function(input)

            if input.UserInputType
                    == Enum.UserInputType.MouseButton1
                or input.UserInputType
                    == Enum.UserInputType.Touch
            then

                dragging =
                    false

            end

        end)

    end


    -- ========================================================
    -- DESTROY
    -- ========================================================

    function Window:Destroy()

        if self.Destroyed then
            return
        end


        self.Destroyed =
            true


        self:
        CloseDropdown()


        pcall(function()

            ScreenGui:
            Destroy()

        end)


        pcall(function()

            ToggleGui:
            Destroy()

        end)

    end


    Close.MouseButton1Click:
    Connect(function()

        Window:
        Destroy()

    end)


    return Window
end


return UI