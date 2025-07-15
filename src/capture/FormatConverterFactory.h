// FormatConverterFactory.h
#pragma once

#include <memory>
#include "IFormatConverter.h"

class FormatConverterFactory {
public:
    // Create the best available format converter for the current platform
    static std::unique_ptr<IFormatConverter> Create();
};
