#include "miniaudio.h"
#include <assert.h>
#include <stdlib.h>

ma_result mazig_device_init(ma_context* context, const ma_device_config* config, ma_device** device)
{
	assert(device != NULL);
	*device = malloc(sizeof(ma_device));
	return ma_device_init(context, config, *device);
}

ma_result mazig_device_uninit(ma_device* device)
{
	ma_device_uninit(device);
	free(device);
}

ma_result mazig_context_init(ma_context** context)
{
	assert(context != NULL);
	*context = malloc(sizeof(ma_context));
	return ma_context_init(NULL, 0, NULL, *context);
}

ma_result mazig_log_init(const ma_allocation_callbacks* callbacks, ma_log** log)
{
	assert(log != NULL);
	*log = malloc(sizeof(ma_log));
	return ma_log_init(callbacks, *log);
}
